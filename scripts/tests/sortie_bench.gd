extends SceneTree

## THE SORTIE LAYER (GAMEPLAY-DESIGN H9, Iteration 6): the reference pilot flies
## COMPOSED SORTIES, and the harness measures the difficulty back out.
##
## This is the instrument H7's debt has been waiting for. H6 is explicit that
## **SDI is measured, never authored**: the composer sets inputs (garrison,
## cover, weather, pads, escalation, fortification) and something has to fly the
## result to read the difficulty out of it. Until now nothing did, so the only
## difficulty signal in the project came from `war_soak`'s abstract proxy — a
## coin weighted by a `skill` float, calibrating a game nobody was playing.
##
## S4 is the reason this exists rather than more duels: *"duels prove
## feel-promises; sorties produce curves."* A duel ends when the enemy dies, so
## it cannot hold a pilot in the threat envelope; a sortie has a TASK, and the
## exposure is the point.
##
## WHAT IT MEASURES, per node: the completion rate over N reps, the fraction of
## hull spent, the time taken, and the dent delivered. The completion rate is
## the SDI; everything else is the shading H6 asks for.
##
## ---------------------------------------------------------------------------
## THREE STATED LIMITS. Each is a real boundary on what a number here means.
##
## 1. **IT DOES NOT FLY THE EGRESS.** A strike ends when the pilot gets back out
##    past 105 m, and `ReferencePilot` has no egress behaviour at all — it
##    orbits and shoots. Teaching it to leave would be a pilot behaviour change,
##    which costs a PILOT_VERSION bump and a full ~45 min re-measure of every
##    other cell on the board. So the bench measures **up to the egress
##    opening** and grants the trip home. A completion here therefore means "the
##    objective died and the pilot was alive to leave", which is the fight and
##    not the whole sortie.
## 2. **THE RETARGETING POLICY IS THE BENCH'S, NOT THE PILOT'S.** The pilot
##    takes one `target` and flies it; deciding WHAT to shoot in a
##    multi-unit fight is a commander's judgement the pilot does not have. The
##    policy below is deliberately simple and stated, so a number can be read as
##    "the model under THIS policy" rather than as an unqualified difficulty.
## 2b. **IT FLIES THE GAME'S INGRESS SINCE 2026-08-03, so numbers taken before
##    that date are not comparable to numbers taken after it.** The pilot used to
##    start at a rig-invented 125 m on a fixed bearing; it now starts on the
##    node's own approach (`SortieRunner.ingress_transform`), which is 140-195 m
##    depending on the biome. Everything else about the sweep is unchanged, so a
##    run at identical settings across that boundary is a clean A/B on the
##    ingress itself — see BALANCE.md.
## 3. **REPS ARE NOT INDIVIDUALLY REPRODUCIBLE, AND THAT IS THE POINT.** The
##    runner seeds its own layout from the spec, so every rep faces the same
##    garrison in the same places — but flyers self-randomize their AI in
##    `_ready` and the runner does not stamp `ai_seed` the way the duel harness
##    does. The RATE over reps is the measurement; no single rep is.
##
## Run: <godot> --headless -s scripts/tests/sortie_bench.gd --path .
##      pass a filter after `--` to narrow it, and drop --headless to WATCH.

## Defaults for a quick sweep. THE LONG RUN OVERRIDES BOTH from the command line
## (`-- --reps 3 --cap 300`) rather than by editing them, because a bench whose
## settings live in a commit is a bench whose numbers cannot be compared to
## anything: BALANCE.md's standing rule is that runs are only comparable at
## IDENTICAL settings, so the settings belong in the invocation and the header.
##
## Rep count is a resolution decision, not a patience one. At 2 reps a rate can
## only be 0%, 50% or 100%, and H6's bands (70-85%, 45-65%, 30-50%) are finer
## than that — so a 2-rep sweep cannot say whether a node is in band.
const REPS: int = 2
## Cap per rep. P2.q6 targets 4-8 minute sorties for a human; the reference
## pilot is faster and a bench that waits that long cannot sweep a theater.
## A rep that hits the cap is a FAILURE to complete, which is a measurement -
## but only if the cap is not the thing doing the failing. The first value was
## 75 s and flak TIMED OUT on 2 of 3 reps at node 8 while out-denting the blaster
## 9.6 to 0.4: it was winning the fight and the clock stopped it. A cap that
## truncates the answer weapon measures the cap.
const MAX_SECONDS: float = 150.0
const THEATER_SEED: int = 4242
## Sorties are laid out around here, clear of the origin so nothing inherits a
## stale arena assumption.
const ARENA_CENTER := Vector3.ZERO
const SPAWN_ALTITUDE: float = 14.0
## WHERE THE PILOT STARTS IS NO LONGER THIS BENCH'S DECISION (A6, 2026-08-03).
##
## It used to be `SPAWN_DISTANCE = 125.0` on a fixed +Z bearing — a rig invented
## here because the game had no ingress to borrow. The game has one now, so the
## bench takes it: `SortieRunner.ingress_transform` puts the pilot on the node's
## own approach, at the range its biome earns (140 m through a city, 195 m over
## open plains) and on the bearing the spec carries. An instrument that measures
## a different approach from the one the player flies is measuring a different
## game, and the whole point of the sortie layer is that it does not.
##
## THE ONE DEVIATION, stated because it changes what a number here means: the
## game puts the pilot on the DECK and the bench keeps them at cruise altitude.
## `ReferencePilot` has no take-off behaviour, and teaching it one is a pilot
## behaviour change — a `PILOT_VERSION` bump and a full re-measure of every cell
## on the board. So the bench flies the right distance and the right bearing at
## the wrong height, and a human's first ten seconds are climb that this does not
## model.
##
## The old constant's scar is kept because its lesson still bounds the band:
## **the first value was 90 and it was measuring the wrong thing.** The outer ring
## sits at 74 +/- 9, so it reaches 83 - and a turret's 45 m sight range meant a
## mid-ring emplacement could open fire on the spawn point before the pilot had
## moved. Node 8 died in 5.3 s with a dent of 0.6, which reads as a crushing
## sortie and was actually a rig placing the pilot inside the envelope with no
## approach. The shipped ingress floor is 140 m, comfortably past that.

## The gun director's solution window, matching the duel harness exactly.
##
## THIS HAS TO BE SET AND IT IS EASY TO MISS. `default_combat_config.tres` ships
## `fire_assist_miss_m = 0.0`, i.e. the director OFF, and every other bench sets
## it per cell — so a bench that simply forgets inherits the MANUAL path (a bare
## 6 deg cone with no ballistic solution) without any symptom except bad numbers.
## The first runs here read 0% completion with a dent of 0.6, which looks exactly
## like a crushing sortie and was actually a pilot that could not shoot. Read
## alongside `Weapon.director_active()`, which is the pilot's trigger rule.
const DIRECTOR_MISS_M: float = 1.2

## Retargeting policy (limit 2 above). Threats inside this range outrank the
## objective: a pilot that ignores a raider on its tail to keep hammering a wall
## is not modelling anything real. Outside it, the objective is the job.
const THREAT_PRIORITY_RANGE: float = 60.0
## How often the policy re-decides. Every tick would make the pilot jitter
## between two equidistant targets and never settle on either.
const RETARGET_PERIOD_S: float = 0.5

var _cells: Array[Dictionary] = []
var _filtered: bool = false
var _watching: bool = false
var _pending_build: bool = false

var _cell_i: int = 0
var _rep: int = 0
var _ticks: int = 0
var _ticks_max: int
## Live settings, overridable from the command line (see `_read_settings`).
var _reps: int = REPS
var _max_seconds: float = MAX_SECONDS
## The name filter, with the setting flags removed - otherwise `--cap 300` is a
## filter no cell name contains and the sweep silently matches nothing.
var _filter_words: String = ""

var _arena: Node3D
var _drone: FlightController
var _health: Health
var _runner: SortieRunner
var _pilot: ReferencePilot
var _hud: Node

var _player_max: float = 1.0
var _finished: bool = false
var _result: Dictionary = {}
var _retarget_timer: float = 0.0
var _results: Array[Dictionary] = []
var _failures: PackedStringArray = []


func _initialize() -> void:
	_watching = BenchView.watching()
	BenchView.setup("sortie_bench")
	_read_settings()
	_select_cells()
	if _cells.is_empty():
		print("[sortie_bench] no cells matched the filter")
		quit(1)
		return
	_ticks_max = int(_max_seconds * float(Engine.physics_ticks_per_second))
	print("[sortie_bench] %d sorties x %d reps, %.0fs cap  (pilot v%d, theater %d)"
			% [_cells.size(), _reps, _max_seconds, ReferencePilot.PILOT_VERSION,
			THEATER_SEED])
	if _filtered:
		print("[sortie_bench] FILTERED RUN - this is a LOOK, not a measurement:")
		print("[sortie_bench] it writes no artifact and asserts nothing.")
	# Built on the first PHYSICS FRAME, never here. During `_initialize` the
	# SceneTree's root will accept an `add_child` and the node is still not
	# `is_inside_tree()`, so `global_position` silently returns identity and the
	# drone's own `_ready` has not resolved its frame config yet — which
	# presents as "arm_throttle_threshold on a base object of type Nil" three
	# calls away from the cause. The duel harness has always done it this way.
	_pending_build = true
	physics_frame.connect(_on_physics_frame)


## Every slice-ready node of one theater, in id order. A theater is the unit
## because H6's curve is a statement about a WAR (pocket -> HQ), not about a
## hand-picked list of fights.
## `-- --reps 3 --cap 300 some filter words`. Anything that is not a recognised
## flag stays in the filter, so the existing "pass words to narrow it" contract is
## unchanged.
func _read_settings() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var words: PackedStringArray = []
	var i: int = 0
	while i < args.size():
		if args[i] == "--reps" and i + 1 < args.size():
			_reps = maxi(int(args[i + 1]), 1)
			i += 2
		elif args[i] == "--cap" and i + 1 < args.size():
			_max_seconds = maxf(float(args[i + 1]), 5.0)
			i += 2
		else:
			words.append(args[i])
			i += 1
	_filter_words = " ".join(words).strip_edges().to_lower()


func _select_cells() -> void:
	var filter: String = _filter_words
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var home := Vector2i(0, 0)
	for node: Dictionary in state["nodes"]:
		if bool(node["home"]):
			home = Vector2i(int(node["q"]), int(node["r"]))
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy":
			continue
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if not SortieComposer.is_slice_ready(spec):
			continue
		var placed: int = 0
		for layer: StringName in SortieComposer.LAYER_ORDER:
			for unit: Dictionary in spec["layers"][layer]:
				placed += int(unit["count"])
		if placed <= 0:
			continue
		var name: String = "node %d %s/%s" % [int(node["id"]), node["type"],
				node["biome"]]
		if filter != "" and not name.to_lower().contains(filter):
			continue
		# THE WEAPON IS AN AXIS, NOT AN ASSUMPTION, and the first runs here proved
		# why. Blaster-only against a node fielding three gnat packs (27 bodies)
		# reads 0% - but P4.3 already says a chip gun loses to a swarm and the
		# duel board already measures `Flak x Gnats` at 100% for 0% hull. That
		# cell was measuring a LOADOUT MISMATCH and labelling it node difficulty.
		# Sweeping all three is the counter-matrix at sortie scale, and the
		# node's real SDI is what its BEST answer achieves.
		for weapon: String in ["blaster", "flak", "missile"]:
			_cells.append({
				"name": "%s %s" % [name, weapon],
				"node": name,
				"weapon": weapon,
				"spec": spec,
				# Hops from the player's home airbase: H6's curve is stated
				# along exactly this axis (pocket -> mid -> deep -> HQ).
				"depth": TheaterGenerator.hex_distance(
						Vector2i(int(node["q"]), int(node["r"])), home),
				"garrison": float(node["garrison"]),
			})
	_filtered = filter != ""


## ---------- one rep ----------

func _build() -> void:
	var cell: Dictionary = _cells[_cell_i]
	_arena = Node3D.new()
	root.add_child(_arena)
	if _watching:
		BenchView.build_scenery(_arena)
		if _hud == null:
			_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
			root.add_child(_hud)
	_arena.add_child(ProjectilePool.new())

	# BALANCE.md's third ruler: benches build through Frames.build, which
	# refuses `user://` overrides. An instrument measures what is committed.
	_drone = Frames.build(Frames.KESTREL)
	_arena.add_child(_drone)
	# The game's ingress, at the bench's altitude (see SPAWN_ALTITUDE's note).
	# Transform, not position: facing the target is part of the approach, and the
	# old rig only got that for free because +Z and an identity basis happened to
	# agree.
	var ingress: Transform3D = SortieRunner.ingress_transform(
			cell["spec"], ARENA_CENTER)
	ingress.origin.y = ARENA_CENTER.y + SPAWN_ALTITUDE
	_drone.global_transform = ingress
	_health = _drone.get_node("Health") as Health
	_player_max = _health.max_health
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())

	_runner = SortieRunner.new()
	_runner.center = ARENA_CENTER
	_arena.add_child(_runner)
	_finished = false
	_result = {}
	_runner.sortie_finished.connect(_on_finished)
	# Limit 1: the pilot cannot fly an egress, so the bench grants the trip home
	# the moment the objective opens it.
	_runner.egress_opened.connect(func() -> void: _runner.force_egress())
	_runner.start(cell["spec"], _drone)

	var weapon_id: String = String(cell.get("weapon", "blaster"))
	var weapon: Weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	# Director for the GUN only, exactly as the duel harness does it: the pod and
	# the rack never had one, so arming it for them would measure a weapon that
	# does not ship.
	weapon.combat_config.fire_assist_miss_m = 			DIRECTOR_MISS_M if weapon_id == "blaster" else 0.0
	_pilot = ReferencePilot.new()
	_pilot.drone = _drone
	_pilot.weapon = weapon
	_pilot.missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_pilot.flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod
	_pilot.weapon_id = weapon_id
	_pilot.cruise_altitude = SPAWN_ALTITUDE
	_retarget_timer = 0.0
	_retarget()
	_ticks = 0
	if _watching:
		BenchView.follow(_drone)
		print("[sortie_bench] --- %s, rep %d/%d ---"
				% [cell["name"], _rep + 1, _reps])


func _on_physics_frame() -> void:
	if _pending_build:
		_pending_build = false
		_build()
		return
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	_ticks += 1
	if _pilot != null:
		_retarget_timer -= delta
		if _retarget_timer <= 0.0:
			_retarget_timer = RETARGET_PERIOD_S
			_retarget()
		_pilot.update(delta)

	if _finished:
		_record(&"complete" if bool(_result.get("objective_complete", false))
				else &"partial")
		return
	if not _health.alive:
		# The runner prices what was broken on the way down (P2.q4), which is
		# the whole reason a death is a measurement rather than a discard.
		_runner.abort("pilot down")
		_record(&"lost")
		return
	if _ticks > _ticks_max:
		_runner.abort("out of time")
		_record(&"timeout")


## The bench's targeting policy, stated in the header as limit 2. Nearest live
## THREAT inside the priority range, else the nearest live objective structure,
## else the nearest anything.
func _retarget() -> void:
	var best: Node3D = null
	var best_d: float = INF
	var at: Vector3 = _drone.global_position
	for unit: Node in _runner.units:
		var body: Node3D = _nearest_body(unit, at)
		if body == null:
			continue
		var d: float = at.distance_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	if best != null and best_d <= THREAT_PRIORITY_RANGE:
		_pilot.target = best
		return
	var objective: Node3D = null
	var objective_d: float = INF
	for asset: ObjectiveAsset in _runner.objectives:
		if not is_instance_valid(asset) or not asset.alive():
			continue
		var d: float = at.distance_to(asset.global_position)
		if d < objective_d:
			objective_d = d
			objective = asset
	_pilot.target = objective if objective != null else best


## A unit may be a single body or a container (a gnat cloud). Reach through to
## something that can actually be shot at.
func _nearest_body(unit: Node, at: Vector3) -> Node3D:
	if not is_instance_valid(unit):
		return null
	if unit.has_method("take_hit"):
		return unit as Node3D
	var best: Node3D = null
	var best_d: float = INF
	for child: Node in unit.get_children():
		if not child.has_method("take_hit") or not child is Node3D:
			continue
		var d: float = at.distance_to((child as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = child as Node3D
	return best


func _on_finished(result: Dictionary) -> void:
	_finished = true
	_result = result


func _record(outcome: StringName) -> void:
	var cell: Dictionary = _cells[_cell_i]
	var hull_spent: float = clampf(
			(_player_max - maxf(_health.current, 0.0)) / maxf(_player_max, 1.0), 0.0, 1.0)
	_results.append({
		"cell": _cell_i,
		"outcome": outcome,
		"hull": hull_spent,
		"seconds": float(_ticks) / float(Engine.physics_ticks_per_second),
		"dent": float(_result.get("dent", WarManifest.dent_from_kills(_runner.kills))),
		"objectives": int(_result.get("objectives_destroyed", 0)),
	})
	# Printed ALWAYS, not just when watching: a sweep of this length is run in
	# the background, and a run you cannot read until it finishes is a run you
	# cannot abandon early with anything to show for it.
	print("[sortie_bench]   %-38s rep %d  %-8s hull %3.0f%%  %5.1fs  dent %.1f"
			% [_cells[_cell_i]["name"], _rep + 1, outcome, hull_spent * 100.0,
			float(_ticks) / float(Engine.physics_ticks_per_second),
			float(_result.get("dent", WarManifest.dent_from_kills(_runner.kills)))])
	_teardown()
	_advance()


func _teardown() -> void:
	_pilot = null
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null


func _advance() -> void:
	_rep += 1
	if _rep >= _reps:
		_rep = 0
		_cell_i += 1
	if _cell_i >= _cells.size():
		_report()
		return
	# One frame for the freed arena to actually leave the tree, or the next
	# sortie's placement casts hit the last one's structures. The pads already
	# learned this lesson the expensive way.
	_pending_build = true


## ---------- the report ----------

func _report() -> void:
	print("")
	print("[sortie_bench] ---- SDI: measured difficulty per node (pilot v%d) ----"
			% ReferencePilot.PILOT_VERSION)
	print("[sortie_bench] completion = the SDI. hull/time/dent are H6's shading.")
	# `dent` and `obj` are the anti-rule-2 columns. A 0% completion is equally
	# consistent with a hard sortie and a broken bench, and the only cheap way to
	# tell them apart is whether the pilot was FIGHTING while it failed: a dent
	# of 0.0 means it never killed anything, which is a rig problem, not a
	# difficulty reading.
	print("[sortie_bench] %-26s %5s %6s %7s %6s %6s %6s %5s  %s"
			% ["node", "depth", "garr", "complete", "hull", "time", "dent",
			"obj", "outcomes"])
	for i: int in _cells.size():
		var cell: Dictionary = _cells[i]
		var reps: Array[Dictionary] = []
		for r: Dictionary in _results:
			if int(r["cell"]) == i:
				reps.append(r)
		if reps.is_empty():
			continue
		var complete: int = 0
		var hull: float = 0.0
		var seconds: float = 0.0
		var dent: float = 0.0
		var objectives: float = 0.0
		var tally: Dictionary = {}
		for r: Dictionary in reps:
			if r["outcome"] == &"complete":
				complete += 1
			hull += float(r["hull"])
			seconds += float(r["seconds"])
			dent += float(r["dent"])
			objectives += float(r["objectives"])
			tally[r["outcome"]] = int(tally.get(r["outcome"], 0)) + 1
		var parts: PackedStringArray = []
		for key: StringName in tally:
			parts.append("%s %d" % [key, int(tally[key])])
		var n: float = float(reps.size())
		if dent <= 0.0:
			_failures.append("%s: dent 0.0 over %d reps - the pilot never killed anything, which is a rig fault rather than a difficulty reading"
					% [cell["name"], reps.size()])
		print("[sortie_bench] %-26s %5d %6.1f %6.0f%% %5.0f%% %5.1fs %6.1f %5.1f  %s"
				% [cell["name"], int(cell["depth"]), float(cell["garrison"]),
				float(complete) / n * 100.0, hull / n * 100.0, seconds / n,
				dent / n, objectives / n, " ".join(parts)])
	_print_best_answers()
	_print_curve()


## THE NODE'S SDI IS WHAT ITS BEST ANSWER ACHIEVES, not what an arbitrary
## loadout achieves. P3's whole thesis is that the arsenal answers the matrix,
## so grading a node by a weapon it hard-counters would measure the mismatch and
## call it difficulty. This is the counter-matrix (P4.3) at sortie scale.
func _print_best_answers() -> void:
	print("")
	print("[sortie_bench] ---- each node's BEST answer (this is the node's SDI) ----")
	var by_node: Dictionary = {}
	for i: int in _cells.size():
		var node_name: String = String(_cells[i]["node"])
		var complete: int = 0
		var reps: int = 0
		for r: Dictionary in _results:
			if int(r["cell"]) != i:
				continue
			reps += 1
			if r["outcome"] == &"complete":
				complete += 1
		if reps == 0:
			continue
		var rate: float = float(complete) / float(reps)
		# Tie-broken on DENT, which matters because every weapon reading 0% is
		# the common case right now: "nothing completed" is not the same finding
		# as "nothing touched it", and the dent is what separates the answer
		# weapon from the mismatched one.
		var dent: float = 0.0
		for r: Dictionary in _results:
			if int(r["cell"]) == i:
				dent += float(r["dent"])
		dent /= float(reps)
		var better: bool = not by_node.has(node_name) 				or rate > float(by_node[node_name]["rate"]) 				or (is_equal_approx(rate, float(by_node[node_name]["rate"]))
						and dent > float(by_node[node_name]["dent"]))
		if better:
			by_node[node_name] = {"rate": rate, "dent": dent,
					"weapon": _cells[i]["weapon"], "depth": _cells[i]["depth"]}
	var names: Array = by_node.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
			return int(by_node[a]["depth"]) < int(by_node[b]["depth"]))
	for node_name: String in names:
		var row: Dictionary = by_node[node_name]
		print("[sortie_bench]   %-26s depth %d  best %-8s %3.0f%%  (dent %.1f)"
				% [node_name, int(row["depth"]), row["weapon"],
				float(row["rate"]) * 100.0, float(row["dent"])])
	if _filtered:
		print("[sortie_bench] filtered LOOK - no assertions run.")
		quit(0)
		return
	if _failures.is_empty():
		print("[sortie_bench] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[sortie_bench] FAIL: %s" % f)
		quit(1)


## H6's curve, as a readout rather than an assertion.
##
## DELIBERATELY NOT ASSERTED YET, and the reason matters: H6's bands describe a
## war fought with an EARNED loadout and a chosen frame, and this bench flies a
## stock Kestrel with a blaster at every node. Failing a board because the
## default loadout cannot crack a deep node would be asserting the wrong claim
## loudly. The gradient is printed so a human can read it; turning it into a
## build break waits for the loadout economy (P5) to exist.
func _print_curve() -> void:
	print("")
	print("[sortie_bench] ---- the H6 gradient, by depth from home ----")
	var by_depth: Dictionary = {}
	for i: int in _cells.size():
		var depth: int = int(_cells[i]["depth"])
		if not by_depth.has(depth):
			by_depth[depth] = {"complete": 0, "reps": 0, "hull": 0.0, "cleared": 0.0}
		var garrison: float = maxf(float(_cells[i]["garrison"]), 0.001)
		for r: Dictionary in _results:
			if int(r["cell"]) != i:
				continue
			by_depth[depth]["reps"] = int(by_depth[depth]["reps"]) + 1
			by_depth[depth]["hull"] = float(by_depth[depth]["hull"]) + float(r["hull"])
			# CLEARED FRACTION: how much of the node the pilot actually took apart
			# before it died. See the print below for why this is here.
			by_depth[depth]["cleared"] = float(by_depth[depth]["cleared"]) 					+ float(r["dent"]) / garrison
			if r["outcome"] == &"complete":
				by_depth[depth]["complete"] = int(by_depth[depth]["complete"]) + 1
	var depths: Array = by_depth.keys()
	depths.sort()
	for depth: int in depths:
		var row: Dictionary = by_depth[depth]
		var reps: int = int(row["reps"])
		if reps == 0:
			continue
		print("[sortie_bench]   %d hop(s) out: %3.0f%% complete, %3.0f%% cleared, %3.0f%% hull, %d reps"
				% [depth, float(row["complete"]) / float(reps) * 100.0,
				float(row["cleared"]) / float(reps) * 100.0,
				float(row["hull"]) / float(reps) * 100.0, reps])
	print("[sortie_bench] H6 wants pocket 70-85%, mid 45-65%, deep 30-50%, HQ 25-40%")
	# WHY THE SECOND COLUMN EXISTS (2026-08-03). The first full-theater sweep -
	# 78 cells, 234 reps, all seven archetypes - returned 0% complete at EVERY
	# depth from 3 to 10. A saturated column has no resolution: every node reads
	# identical and the curve H6 asks for cannot be seen at all.
	#
	# The signal was in the dent the whole time. `cleared` is the fraction of the
	# node's own strength the pilot took apart before dying, and across that same
	# sweep it fell 54% -> 21% from depth 3 to depth 7 - a real gradient, in a
	# metric that does not saturate when the pilot always dies. It is the SHAPE
	# H6 wants even though it is not the UNIT H6 named.
	print("[sortie_bench] `cleared` is the fraction of the node taken apart before dying:")
	print("[sortie_bench] it keeps its resolution when `complete` saturates at 0%.")
	print("[sortie_bench] read against a STOCK KESTREL + BLASTER - no earned loadout,")
	print("[sortie_bench] no frame choice, so a low deep number is expected here.")
