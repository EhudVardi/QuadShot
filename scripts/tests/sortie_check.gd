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
## The trigger probe's own egress counter. A MEMBER, not a local captured by a
## lambda: GDScript closures capture locals BY VALUE, so `opened += 1` inside the
## handler incremented a copy and every "no egress yet" assertion passed without
## ever being able to fail.
var _probe_egress: int = 0
var _probed: bool = false


func _initialize() -> void:
	_check_spec_shape()
	_check_every_trigger_has_a_firing_site()
	_check_ingress()
	if not _failures.is_empty():
		_report()
		return
	_sweep_archetypes_then_fly()


## The archetype sweep needs a frame between building a structure and hitting it
## (an `ObjectiveAsset` has no `Health` until its `_ready` runs), so it is a
## coroutine and the flown stages start after it.
func _sweep_archetypes_then_fly() -> void:
	await _check_every_archetype_can_end()
	_start_flying()


func _start_flying() -> void:
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


## THE CHECK THAT WOULD HAVE CAUGHT `detected` (Iteration 13, the archetype
## opening). A reserve keyed to an event nothing ever fires is the worst kind of
## broken, because it is INVISIBLE from every direction a test normally looks:
##
##   - the composer is correct - it emitted the trigger it was asked for,
##   - the runner is correct - it fires the triggers it is told about,
##   - the sortie completes, so no deadlock check notices,
##   - and the fight is quietly EASIER than the node it came from, because
##     reserves are taken OUT of the placed garrison (P2.3), so the held slice
##     simply never arrives.
##
## `SLICE_ARCHETYPES` was `[strike, dogfight]` for all of Iteration 12, and those
## two use `objective_damaged` and `wave_cleared`. The moment the other five
## opened, three of them keyed reserves to `detected` — which had no firing site
## anywhere in the project.
##
## So: every value in `TRIGGER_ON` must appear in a `_fire_trigger` call in the
## runner's own source. It is a structural assertion rather than a behavioural
## one, and it is the only kind that can fail for a trigger nobody has thought to
## write a scenario for yet.
func _check_every_trigger_has_a_firing_site() -> void:
	var source: String = (load("res://scripts/sortie/sortie_runner.gd") as GDScript) \
			.source_code
	var unfired: PackedStringArray = []
	for archetype: StringName in SortieComposer.TRIGGER_ON:
		var on: StringName = SortieComposer.TRIGGER_ON[archetype]
		if not source.contains('_fire_trigger(&"%s")' % on):
			unfired.append("%s -> %s" % [archetype, on])
	_expect(unfired.is_empty(),
			"every archetype's trigger has a firing site in the runner (orphaned: %s)"
			% ", ".join(unfired))


## EVERY ARCHETYPE MUST BE ABLE TO FINISH — swept, not sampled.
##
## Five archetypes opened at once (2026-08-01), and the failure they share is the
## one this file was written for: a sortie the pilot cannot end. The two flown
## stages below prove it for a strike and a dogfight in a real arena; proving it
## for the other five that way would cost five more flights, so they are proved
## structurally instead — flatten the structures, and the way home must open.
##
## The `detected` assertion is the behavioural half of the source-scan above:
## the source-scan proves the firing site EXISTS, this proves it FIRES.
func _check_every_archetype_can_end() -> void:
	for archetype: StringName in SortieComposer.SLICE_ARCHETYPES:
		var recipe: Dictionary = {}
		for node_type: StringName in SortieComposer.ARCHETYPES:
			if SortieComposer.ARCHETYPES[node_type]["archetype"] == archetype:
				recipe = SortieComposer.ARCHETYPES[node_type]
				break
		if recipe.is_empty():
			_fail("%s is slice-ready and no node type produces it" % archetype)
			continue

		var host := Node3D.new()
		root.add_child(host)
		var runner := SortieRunner.new()
		runner.center = Vector3(400.0, 0.0, 400.0)  # clear of anything else
		host.add_child(runner)

		var assets: int = int(recipe["assets"])
		var spec: Dictionary = _bare_spec(archetype, recipe["objective"], assets)
		# A reserve on this archetype's own trigger, so firing it is observable.
		spec["triggers"] = [{
			"on": SortieComposer.TRIGGER_ON[archetype], "wave": 1, "after_s": 0.05,
			"units": [{"type": &"raider", "count": 1, "bodies": 1, "strength": 1.0}],
		}]
		runner.start(spec)
		# ONE FRAME BEFORE TOUCHING ANYTHING. An ObjectiveAsset builds its Health
		# in `_ready`, and `take_hit` returns silently while that is null - so a
		# synchronous version of this sweep reported every archetype as unable to
		# open its egress, and every reserve as never firing. Both were the test
		# hitting a structure that did not exist yet.
		await process_frame

		_expect(runner.objectives.size() == assets,
				"%s builds its %d objective structure(s) (got %d)"
				% [archetype, assets, runner.objectives.size()])

		if assets == 0:
			# The dogfight's ending is the field-cleared path, flown below.
			_expect(runner.phase == SortieRunner.Phase.ENGAGED,
					"%s starts engaged with no structure to flatten" % archetype)
			host.queue_free()
			continue

		var before_unfired: int = runner.reserves_unfired()
		for asset: ObjectiveAsset in runner.objectives.duplicate():
			asset.take_hit(99999.0)
		_expect(runner.phase == SortieRunner.Phase.EGRESS,
				"%s opens the way home once its objective is flat (phase %d)"
				% [archetype, runner.phase])
		# Every objective archetype's trigger is reachable by touching the
		# objective: `objective_damaged` directly, `detected` through
		# `_announce_yourself`. A reserve that never fires is a garrison slice
		# that never arrives, and the fight is quietly easier than the node.
		_expect(runner.reserves_unfired() < before_unfired,
				"%s fires its '%s' reserve when the pilot announces themselves"
				% [archetype, SortieComposer.TRIGGER_ON[archetype]])
		host.queue_free()


## THE INGRESS (Iteration 14 / A6), which REPLACED the check that used to sit
## here.
##
## What was here: "a garrison that cannot see its own objective is not a
## garrison" — every unit had to be placed within `sight_range` of the centre,
## which is what v2.12's `SIGHT_COVERAGE` clamp guaranteed. It was the right
## assertion about the wrong world. `EnemyDrone._can_engage()` measures its
## distance to the PLAYER, not to the objective, so the clamp was really saying
## "every unit must be able to see a pilot standing in the middle" — true only
## because there was no ingress and the pilot started there. With an approach to
## defend, a mid-ring turret 57 m out covering the annulus a pilot has to cross
## is doing its job precisely BY not hugging the centre, and the old check would
## have failed it.
##
## What replaces it is the geometry the pilot's whole approach hangs off, and the
## three things that can silently break it:
##
##   - the spawn drifting INSIDE `EGRESS_RADIUS`, which puts the pilot on the far
##     side of the line a strike ends by crossing — the sortie would be
##     half-over before it started;
##   - the spawn drifting OUTSIDE the FPV link's warning radius, which greets the
##     pilot with SIGNAL WEAK before they have moved. The leash and the ingress
##     are tuned in two different files and nothing else connects them;
##   - the bearing quietly not being read at all. A constant would pass every
##     distance assertion above and be invisible, so the last two assertions are
##     about VARIATION: the point has to sit on the spec's own bearing, and two
##     nodes with different `ingress_m` have to land at different ranges.
func _check_ingress() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var center := Vector3(-18.0, 0.0, -15.0)

	# The leash's own numbers, read off the scene's script rather than retyped, so
	# retuning one of the two files cannot leave this assertion agreeing with a
	# radius nobody flies. `new()` on a Node3D script never runs `_ready`, so no
	# @onready node paths are touched.
	var probe: Node = (load("res://scripts/sortie.gd") as GDScript).new()
	var warn_m: float = float(probe.get(&"signal_warn_m"))
	probe.free()

	var checked: int = 0
	var ranges: Dictionary = {}   # ingress_m (fiction) -> world range
	var too_close: int = 0
	var too_far: int = 0
	var off_bearing: int = 0
	var facing_away: int = 0
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if not SortieComposer.is_slice_ready(spec):
			continue
		checked += 1
		var at: Transform3D = SortieRunner.ingress_transform(spec, center)
		var flat: Vector3 = at.origin - center
		flat.y = 0.0
		var range_m: float = flat.length()
		ranges[float(spec["approach"]["ingress_m"])] = range_m
		# Outside the fight, with enough room that the trip in is a leg of the
		# sortie rather than a nudge over the line.
		if range_m < SortieRunner.EGRESS_RADIUS + 25.0:
			too_close += 1
		if range_m > warn_m - 20.0:
			too_far += 1
		# On the spec's bearing, to a degree.
		if flat.normalized().angle_to(SortieRunner.ingress_direction(spec)) > 0.02:
			off_bearing += 1
		# And pointed at the target: drone front is body -Z.
		if (-at.basis.z).angle_to(-flat.normalized()) > 0.02:
			facing_away += 1

	_expect(checked > 0, "the theater offers sorties to compute an ingress for (%d)" % checked)
	_expect(too_close == 0,
			"every ingress starts outside the egress line by 25 m or more (%d too close)"
			% too_close)
	_expect(too_far == 0,
			"and inside the FPV link's %d m warning with room to drift (%d too far)"
			% [int(warn_m), too_far])
	_expect(off_bearing == 0,
			"every ingress sits on the bearing its spec carries (%d off)" % off_bearing)
	_expect(facing_away == 0,
			"and the pilot is put down facing the target (%d pointed away)" % facing_away)
	# The anti-constant assertion: if the theater offers two different approaches,
	# the runner must place them at two different distances, or `ingress_m` is
	# being ignored exactly as it was before this landed.
	var distinct_specs: int = ranges.size()
	var distinct_ranges: Dictionary = {}
	for key: float in ranges:
		distinct_ranges[ranges[key]] = true
	_expect(distinct_specs < 2 or distinct_ranges.size() > 1,
			"different approaches give different ingress ranges (%d specs -> %d ranges)"
			% [distinct_specs, distinct_ranges.size()])


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
## THIS USED TO ASSERT NOTHING. The first version appended to `_triggers` and
## `_trigger_spent` by hand, flipped a flag by hand, and checked that a two-element
## array had two elements - `_fire_trigger` was never called, so deleting it
## outright would have left this green. It was also unable to regress the bug it
## names, because the structure it inspected is the Array that REPLACED the
## Dictionary-keyed flags. Now it drives the real function, in a real tree.
##
## The assertion that matters is the last pair: FIRED IS NOT ARRIVED. A reserve
## on its timer is a wave you still have to meet, and reading the spent flag as
## "held" let a dogfight announce AIRSPACE CLEAR in the same frame it announced
## reserves inbound.
func _check_trigger_selection() -> void:
	var runner := SortieRunner.new()
	var spec: Dictionary = _bare_spec(&"dogfight", &"clear_airspace", 0)
	spec["triggers"] = [
		{"on": &"wave_cleared", "wave": 1, "after_s": 30.0, "units": []},
		{"on": &"wave_cleared", "wave": 2, "after_s": 30.0, "units": []},
	]
	# In the tree, because `_fire_trigger` starts a real SceneTreeTimer. The long
	# `after_s` guarantees nothing releases on its own inside this function.
	root.add_child(runner)
	runner.egress_opened.connect(func() -> void: _probe_egress += 1)
	runner.spec = spec
	runner.phase = SortieRunner.Phase.ENGAGED
	for trigger: Dictionary in spec["triggers"]:
		runner._triggers.append(trigger)
		runner._trigger_spent.append(false)
		runner._trigger_released.append(false)
	_expect(runner.reserves_held() == 2, "two structurally similar reserves stay distinct")

	runner._fire_trigger(&"wave_cleared")
	_expect(runner.reserves_unfired() == 1,
			"firing takes exactly one reserve, not both (%d left to summon)"
			% runner.reserves_unfired())
	_expect(runner.reserves_held() == 2,
			"but nothing has ARRIVED yet - an inbound wave is still held (%d)"
			% runner.reserves_held())
	# The empty field must NOT read as clear while a wave is on its timer.
	runner._check_field_cleared()
	_expect(_probe_egress == 0,
			"an empty field with a reserve inbound is not AIRSPACE CLEAR")

	runner._fire_trigger(&"wave_cleared")
	_expect(runner.reserves_unfired() == 0, "the second clear takes the second reserve")
	_expect(runner.reserves_held() == 2, "and both are still inbound")
	runner._fire_trigger(&"wave_cleared")
	_expect(runner.reserves_unfired() == 0, "a third clear summons nothing that is not there")

	runner._release(0)
	_expect(runner.reserves_held() == 1, "a released reserve stops being held")
	_expect(_probe_egress == 0, "one wave arriving does not end the sortie while one is out")
	runner._release(1)
	_expect(runner.reserves_held() == 0, "and the last one arriving clears the board")
	_expect(_probe_egress == 1,
			"only THEN does the empty field open the egress, exactly once (%d)"
			% _probe_egress)
	runner.queue_free()


func _bare_spec(archetype: StringName, objective: StringName,
		assets: int) -> Dictionary:
	return {
		"version": 1, "seed": 7, "truth": true, "node_id": 0,
		"archetype": archetype, "objective": objective,
		"objective_assets": assets, "triggers": [],
		"layers": {&"outer": [], &"mid": [], &"inner": []},
	}


## AUDIT F6: A RESERVE FIRED IN ONE SORTIE MUST NOT ARRIVE IN THE NEXT ONE.
##
## `_fire_trigger` hands a `SceneTreeTimer` a callable bound to an INDEX into
## three arrays that `start()` clears and rebuilds, and the timer belongs to the
## tree rather than to the runner. `phase == DONE` did not cover the gap, because
## starting the next sortie sets ENGAGED again.
##
## What it would do, if a runner were reused: mark one of sortie B's reserves as
## ARRIVED without it ever firing — which can open B's egress early, since
## `reserves_held` gates it — and spawn A's units into B's arena, where they are
## appended to B's unit list and credited to B's dent.
##
## Nothing shipped is affected: `sortie.gd` and `sortie_bench.gd` build a fresh
## runner per sortie. This check exists so that stays true by assertion rather
## than by nobody having tried it.
##
## It uses a REAL timer with a short fuse rather than calling `_release` by hand,
## because calling it by hand is precisely the thing that cannot reproduce the
## bug — the trap is that the timer outlives the sortie.
func _check_reserve_does_not_leak_into_the_next_sortie() -> void:
	var runner := SortieRunner.new()
	root.add_child(runner)

	var first: Dictionary = _bare_spec(&"dogfight", &"clear_airspace", 0)
	first["triggers"] = [
		{"on": &"wave_cleared", "wave": 1, "after_s": 0.05,
			"units": [{"type": &"raider", "count": 3, "bodies": 3, "strength": 3.0}]},
	]
	runner.start(first)
	runner._fire_trigger(&"wave_cleared")
	_expect(runner.reserves_unfired() == 0, "sortie A's reserve is on its timer")

	# Sortie B starts before A's fuse runs out - one placed raider, two reserves.
	var second: Dictionary = _bare_spec(&"dogfight", &"clear_airspace", 0)
	second["layers"][&"outer"] = [{"type": &"raider", "count": 1, "bodies": 1,
			"strength": 1.0}]
	second["triggers"] = [
		{"on": &"wave_cleared", "wave": 1, "after_s": 60.0, "units": []},
		{"on": &"wave_cleared", "wave": 2, "after_s": 60.0, "units": []},
	]
	runner.start(second)
	var placed: int = runner.remaining()
	_expect(placed == 1, "sortie B places its own garrison (%d)" % placed)
	_expect(runner.reserves_held() == 2, "and holds its own two reserves")

	# Outlast A's 0.05 s fuse by a wide margin.
	for i: int in 40:
		await physics_frame

	_expect(runner.reserves_held() == 2,
			"A's timer does not mark one of B's reserves as arrived (%d held, wanted 2)"
			% runner.reserves_held())
	_expect(runner.remaining() == placed,
			"and does not spawn A's units into B's arena (%d units, wanted %d)"
			% [runner.remaining(), placed])
	_expect(runner.phase == SortieRunner.Phase.ENGAGED,
			"so B is still being flown rather than declared clear (phase %d)" % runner.phase)

	runner.queue_free()
	_stage = 0


## AUDIT F1, THE RUNNER'S HALF: a sortie that starts with nothing in it must
## still be able to END.
##
## The map now refuses to offer such a node (`war_room_check` asserts that), but
## a runner that hangs on an empty spec is a hazard independent of who hands it
## one — a bench, a future caller, a saved spec. The failure is the worst shape
## this file exists for: pilot alive, nothing to shoot, no egress, and quitting
## is defined as losing the sortie.
##
## The PAIR is the point. "An empty spec ends immediately" is satisfied by a
## runner that ends every sortie immediately, so the second half asserts that one
## unit is enough to keep it open.
func _check_empty_spec_can_end() -> void:
	var empty := SortieRunner.new()
	root.add_child(empty)
	var opened: Array[int] = []
	empty.egress_opened.connect(func() -> void: opened.append(1))
	var spec: Dictionary = _bare_spec(&"dogfight", &"clear_airspace", 0)
	_expect(not SortieComposer.has_anything_to_fight(spec),
			"a spec with no units and no structure holds no fight")
	empty.start(spec)
	_expect(empty.phase == SortieRunner.Phase.EGRESS,
			"a sortie with nothing in it opens its egress at once rather than hanging (phase %d)"
			% empty.phase)
	_expect(opened.size() == 1,
			"and says so exactly once (%d)" % opened.size())
	empty.queue_free()

	# The other half: something to fight must NOT end the sortie.
	var live := SortieRunner.new()
	root.add_child(live)
	var live_opened: Array[int] = []
	live.egress_opened.connect(func() -> void: live_opened.append(1))
	var manned: Dictionary = _bare_spec(&"dogfight", &"clear_airspace", 0)
	manned["layers"][&"outer"] = [{"type": &"raider", "count": 1, "bodies": 1,
			"strength": 1.0}]
	_expect(SortieComposer.has_anything_to_fight(manned),
			"one raider is a fight")
	live.start(manned)
	_expect(live.phase == SortieRunner.Phase.ENGAGED,
			"a sortie with a garrison stays ENGAGED (phase %d)" % live.phase)
	_expect(live_opened.is_empty(),
			"and does not hand out an egress nobody earned (%d)" % live_opened.size())
	live.queue_free()


## ---------- Part B: two composed sorties, in a real arena ----------

func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks < 30:
		return
	# The trigger probe needs a LIVE tree (`_fire_trigger` starts a real
	# SceneTreeTimer), and `root.add_child` during `_initialize` does not give it
	# one - the node is parented but not yet inside the tree. Same trap the
	# delivery bench hit building its arena too early.
	if not _probed:
		_probed = true
		_check_trigger_selection()
		_check_empty_spec_can_end()
		if not _failures.is_empty():
			_report()
			return
		# The reserve-leak probe waits on a REAL timer, so it parks the stage
		# machine while it runs and puts it back afterwards.
		_stage = -1
		_check_reserve_does_not_leak_into_the_next_sortie()
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
	_spec = _find_spec(&"dogfight", true)
	if _spec.is_empty():
		_fail("the theater produced no dogfight to fly")
		_report()
		return
	_runner.start(_spec)
	_expect(_runner.remaining() > 0,
			"a composed dogfight places its garrison (%d units)" % _runner.remaining())
	_expect(not _runner.has_objective(), "a dogfight has no structure to flatten")
	_check_pads(_spec)
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
	_check_pads(_spec)
	_stage = 3


## P2.6 / W.q4. The zero case is the one that matters: a heavily garrisoned node
## earns no pads, and a runner that quietly handed out a repair gate anyway
## would delete the composer's only ROUTE-shaped difficulty knob without any
## single line looking wrong.
func _check_pads(spec: Dictionary) -> void:
	var want: int = int(spec["pads"])
	_expect(_runner.pads.size() == want,
			"the sortie lays exactly the pads the composer allowed (%d of %d)"
			% [_runner.pads.size(), want])
	if want == 0:
		return
	# Hull is the resource you cannot fly without, so a one-pad node hands you
	# the green one.
	_expect(_runner.pads[0] is RepairGate,
			"the first pad is the repair gate, whatever else follows")
	for i: int in range(1, _runner.pads.size()):
		_expect(_runner.pads[i] is ResupplyGate,
				"pad %d is a resupply gate" % i)
	# Placed clear of each other and of the structures, or a pad reads as
	# flyable and is not.
	for i: int in _runner.pads.size():
		for asset: ObjectiveAsset in _runner.objectives:
			_expect(_runner.pads[i].position.distance_to(asset.position)
					>= SortieRunner.PAD_OBJECTIVE_CLEARANCE,
					"pad %d clears the structures" % i)
		for j: int in range(i + 1, _runner.pads.size()):
			_expect(_runner.pads[i].position.distance_to(_runner.pads[j].position)
					>= SortieRunner.PAD_MIN_SEPARATION,
					"pads %d and %d do not overlap" % [i, j])


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

## `prefer_pads` picks the richest node of that archetype rather than the first.
## The two stages deliberately take opposite ends of the pad range: pads run 0-2
## across slice-ready nodes, and without steering this the check drew a 1-pad
## dogfight and a 0-pad strike, so the resupply-alternation branch never ran once.
## A branch that never runs is untested however green the board looks.
func _find_spec(archetype: StringName, prefer_pads: bool = false) -> Dictionary:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var best: Dictionary = {}
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if spec["archetype"] != archetype or not SortieComposer.is_slice_ready(spec):
			continue
		# Needs something to actually place, or the stage proves nothing.
		var placed: int = 0
		for layer: StringName in SortieComposer.LAYER_ORDER:
			for unit: Dictionary in spec["layers"][layer]:
				placed += int(unit["count"])
		if placed <= 0:
			continue
		if not prefer_pads:
			return spec
		if best.is_empty() or int(spec["pads"]) > int(best["pads"]):
			best = spec
	return best


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
	for pad: Node3D in _runner.pads:
		if is_instance_valid(pad):
			pad.queue_free()


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
