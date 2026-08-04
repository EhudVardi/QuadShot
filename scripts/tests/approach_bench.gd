extends SceneTree

## THE UNCONTESTED APPROACH (GAMEPLAY-DESIGN v2.16, A.q7).
##
## The user flew the new ingress and reported the thing that matters: *"on both
## cases the enemy did not attack me until i engaged."* Coverage was already
## measured and refuted as the cause — walking the real ingress line for all 30
## nodes of seed 4242, 0 of 30 sorties fail to have the pilot in sight before the
## centre, and the pilot flies a mean of only 49 m unseen. The garrison SEES you.
##
## v2.16 states the inference and, to its credit, states that it is an inference:
## a raider is 14 m/s with an 18 m preferred range, a turret is 0 m/s with 45 m of
## sight, `_try_fire` has no range gate, and *"they shoot and miss and cannot keep
## up"* is NOT yet measured. It then names the one cheap test that settles it:
##
##   > fly a straight-line ingress at cruise speed and log enemy shots fired and
##   > hits landed against distance from the centre. If shots are fired and miss,
##   > this is a speed and lethality finding; if no shots are fired,
##   > `_has_line_of_sight` or the armed gate is the culprit and the diagnosis
##   > above is wrong.
##
## This is that test.
##
## TWO DESIGN DECISIONS, both made to keep the answer readable.
##
## 1. SPEED IS THE INDEPENDENT VARIABLE, not a constant. The hypothesis IS about
##    speed, so picking one "cruise speed" and reporting a single number would beg
##    the question it was built to answer. The same ingress is flown at several
##    speeds and the shape across them is the finding.
##
## 2. THE PILOT IS A SLED, NOT `ReferencePilot`. The question is what the GARRISON
##    can do to a crossing target; a fighting brain would orbit, shoot back and
##    change the geometry, and it carries the cross-process reproducibility debt
##    that currently makes every bench number unattributed (BALANCE.md). A body
##    moved along the spec's own bearing at a fixed speed has no such variance,
##    and it is the honest reading of *"a straight-line ingress at cruise speed"*.
##    Its `linear_velocity` is real, so the enemies' lead solution is the real one
##    — aiming at a stationary reading would flatter them.
##
## WHAT IT MEASURES, per (node, speed):
##   - shots fired by the garrison, detected by each firer's `_cooldown` RISING,
##     which needs no change to production code;
##   - hits landed, off the player's `Health.struck` signal, which exists for
##     exactly this reason (counting arrivals from outcome signals undercounts);
##   - the ENGAGE GATE, decomposed: how many firer-frames failed on range, how
##     many were in range and failed line-of-sight, and how many engaged. That is
##     what separates "shoots and misses" from "never shoots".
##
## Run:  <godot> --headless -s scripts/tests/approach_bench.gd --path .
##       optional: -- --seed 4242 --nodes 8,12,21 --speeds 8,14,20,26
##       drop --headless to watch one.
##
## It writes no artifact and asserts nothing. It is a MEASUREMENT for a human to
## read, and per H6 nothing here licenses a tuning change.

const ARENA_CENTER := Vector3.ZERO
## Matches `sortie_bench.SPAWN_ALTITUDE`: the deck is where an ingress is flown.
const ALTITUDE: float = 14.0
## Stop when the sled reaches this from the centre — past the inner ring, which
## is where "the approach" ends and "the fight" begins.
const ARRIVAL_M: float = 20.0
## Distance bands for the report, outward from the centre.
const BAND_M: float = 25.0
const MAX_SECONDS: float = 90.0

var _seed: int = 4242
var _node_ids: Array[int] = []
var _speeds: Array[float] = [8.0, 14.0, 20.0, 26.0]

var _cells: Array[Dictionary] = []
var _cell_i: int = 0
var _results: Array[Dictionary] = []

var _arena: Node3D
var _drone: FlightController
var _health: Health
var _runner: SortieRunner
var _firers: Array[Node] = []
var _cooldowns: Array[float] = []
var _direction := Vector3.ZERO
var _speed: float = 0.0
var _ticks: int = 0
var _pending_build: bool = true

## Per-cell tallies. Bands are keyed by the integer band index from the centre.
var _shots: Dictionary = {}
var _hits: Dictionary = {}
var _shots_total: int = 0
var _hits_total: int = 0
var _damage_total: float = 0.0
## CONTACT IS NOT A SHOT, and separating them is not optional (found by this
## bench's own first run, which reported `6 shots / 15 hits` on node 8 - a 250%
## hit rate, which is the instrument telling you it is measuring two things and
## calling them one).
##
## `gnat_swarm.gd` stings by distance test and calls `take_hit` directly: no
## projectile, no cooldown, so the shot counter cannot see it while `Health.struck`
## certainly can. A sting also always kills the gnat that delivered it - and this
## sled never fires - so ANY gnat body lost is exactly one sting. That makes the
## split exact rather than a proximity heuristic.
var _stingers: Array[Node] = []
var _sting_bodies: Array[int] = []
var _contact_hits: int = 0
var _contact_damage: float = 0.0
## Shots and engaged gun-frames per bestiary type, and the count of each type
## placed. A.q7's actual question is WHICH type contests an approach.
## Closest approach of each enemy round to the sled, in metres. This is the
## number that decides what KIND of problem a miss is: rounds passing 2 m away
## are an aim or lead problem, rounds passing 30 m away are a solution problem,
## and the two want different answers. Tracked by walking the pool, because a
## projectile carries no signal.
var _misses: Array[float] = []
var _tracked: Dictionary = {}
var _pool: ProjectilePool
var _shots_by_type: Dictionary = {}
var _engaged_by_type: Dictionary = {}
var _placed_by_type: Dictionary = {}
var _frames_engaged: int = 0
var _firer_frames: int = 0
var _out_of_range_frames: int = 0
var _no_los_frames: int = 0
var _engaged_frames: int = 0
var _first_shot_m: float = -1.0
var _first_hit_m: float = -1.0
var _watching: bool = false


func _initialize() -> void:
	_watching = DisplayServer.get_name() != "headless"
	_read_args()
	_build_cells()
	if _cells.is_empty():
		print("[approach] no cells to fly")
		quit()
		return
	print("[approach] %d cells (theater %d), speeds %s"
			% [_cells.size(), _seed, str(_speeds)])
	print("[approach] a SLED flies the spec's own ingress bearing straight in.")
	print("[approach] no return fire, no evasion - this measures the GARRISON.")
	physics_frame.connect(_on_physics_frame)


func _read_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
		elif args[i] == "--nodes" and i + 1 < args.size():
			for piece: String in args[i + 1].split(",", false):
				_node_ids.append(int(piece))
		elif args[i] == "--speeds" and i + 1 < args.size():
			_speeds.clear()
			for piece: String in args[i + 1].split(",", false):
				_speeds.append(float(piece))


func _build_cells() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, _seed)
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy":
			continue
		var id: int = int(node["id"])
		if not _node_ids.is_empty() and not _node_ids.has(id):
			continue
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if not SortieComposer.is_slice_ready(spec) \
				or not SortieComposer.has_anything_to_fight(spec):
			continue
		if _node_ids.is_empty() and _cells.size() >= 4 * _speeds.size():
			break
		for speed: float in _speeds:
			_cells.append({
				"name": "node %d %s/%s" % [id, node["type"], node["biome"]],
				"node": id,
				"spec": spec,
				"speed": speed,
			})


## ---------- one pass ----------

func _build() -> void:
	var cell: Dictionary = _cells[_cell_i]
	_arena = Node3D.new()
	root.add_child(_arena)
	if _watching:
		BenchView.build_scenery(_arena)
	_pool = ProjectilePool.new()
	_arena.add_child(_pool)

	# BALANCE.md's third ruler: build through Frames, which refuses user://
	# overrides, so the instrument measures what is committed.
	_drone = Frames.build(Frames.KESTREL)
	_arena.add_child(_drone)
	var ingress: Transform3D = SortieRunner.ingress_transform(cell["spec"], ARENA_CENTER)
	ingress.origin.y = ARENA_CENTER.y + ALTITUDE
	_drone.global_transform = ingress
	_health = _drone.get_node("Health") as Health
	# `struck` rather than `damaged`: it fires per ARRIVING round, which is what
	# "hits landed" means, and it is the signal that exists because the outcome
	# signals undercount.
	_health.struck.connect(_on_struck)
	_drone.arm()
	# The sled: the flight loop is off and gravity with it, so the body travels
	# the bearing at exactly the stated speed. `armed` stays true because
	# `_can_engage` reads it, and that gate is one of the things under test.
	_drone.set_physics_process(false)
	_drone.gravity_scale = 0.0
	_drone.freeze = false

	_runner = SortieRunner.new()
	_runner.center = ARENA_CENTER
	_arena.add_child(_runner)
	_runner.start(cell["spec"], _drone)

	# Inward along the spec's own bearing, flat: the ingress transform already
	# faces the target, so this is the line the briefing describes.
	var flat := Vector3(ARENA_CENTER.x - ingress.origin.x, 0.0,
			ARENA_CENTER.z - ingress.origin.z)
	_direction = flat.normalized()
	_speed = float(cell["speed"])

	_firers.clear()
	_cooldowns.clear()
	_stingers.clear()
	_sting_bodies.clear()
	_collect_firers(_arena)
	for firer: Node in _firers:
		_cooldowns.append(float(firer.get(&"_cooldown")))
	for stinger: Node in _stingers:
		_sting_bodies.append(_living_bodies(stinger))

	_shots = {}
	_hits = {}
	_shots_total = 0
	_hits_total = 0
	_damage_total = 0.0
	_contact_hits = 0
	_contact_damage = 0.0
	_misses.clear()
	_tracked = {}
	_shots_by_type = {}
	_engaged_by_type = {}
	_placed_by_type = {}
	for firer: Node in _firers:
		var placed_config: EnemyConfig = firer.get(&"enemy_config")
		_placed_by_type[placed_config.type_id] = 				int(_placed_by_type.get(placed_config.type_id, 0)) + 1
	_firer_frames = 0
	_out_of_range_frames = 0
	_no_los_frames = 0
	_engaged_frames = 0
	_frames_engaged = 0
	_first_shot_m = -1.0
	_first_hit_m = -1.0
	_ticks = 0
	if _watching:
		BenchView.follow(_drone)
	print("[approach] --- %s at %.0f m/s, %d firers placed ---"
			% [cell["name"], _speed, _firers.size()])


## Anything that can shoot: an EnemyDrone or a Turret, both of which carry an
## `enemy_config` and a `_cooldown`. Walked rather than read off a group, because
## a gnat cloud is one unit and many bodies.
func _collect_firers(node: Node) -> void:
	if node.get(&"enemy_config") != null and node.get(&"_cooldown") != null:
		var config: EnemyConfig = node.get(&"enemy_config")
		# A screamer carries no weapon at all; counting it as a firer that never
		# fires would report a jam field as a lethality failure.
		if config != null and config.damage > 0.0 and config.fire_rate > 0.0:
			_firers.append(node)
	# A swarm: no gun, no cooldown, damage by reaching you.
	if node.get(&"_bodies") != null and node.get(&"enemy_config") != null:
		_stingers.append(node)
	for child: Node in node.get_children():
		_collect_firers(child)


## Closest approach, per round, while it is in flight. A round that leaves the
## pool has finished, so its running minimum is its miss distance - and a round
## that HIT records ~0, which is correct and keeps the two populations comparable.
##
## Player rounds cannot pollute this: the sled has no trigger.
func _track_misses(at: Vector3) -> void:
	if _pool == null or not is_instance_valid(_pool):
		return
	var live: Dictionary = {}
	for child: Node in _pool.get_children():
		if not (child is Projectile) or not (child as Node3D).visible:
			continue
		var id: int = child.get_instance_id()
		live[id] = true
		var distance: float = (child as Node3D).global_position.distance_to(at)
		if not _tracked.has(id) or distance < float(_tracked[id]):
			_tracked[id] = distance
	# Anything that stopped being in flight this frame has finished its pass.
	for id: int in _tracked.keys():
		if not live.has(id):
			_misses.append(float(_tracked[id]))
			_tracked.erase(id)


## Living bodies in a swarm. Read every frame, because the DROP is the signal.
func _living_bodies(stinger: Node) -> int:
	var bodies: Variant = stinger.get(&"_bodies")
	if not bodies is Array:
		return 0
	var alive: int = 0
	for body: Variant in bodies as Array:
		if body is Node and is_instance_valid(body as Node):
			alive += 1
	return alive


func _on_struck(amount: float) -> void:
	_hits_total += 1
	_damage_total += amount
	var distance: float = _drone.global_position.distance_to(ARENA_CENTER)
	var band: int = int(distance / BAND_M)
	_hits[band] = int(_hits.get(band, 0)) + 1
	if _first_hit_m < 0.0:
		_first_hit_m = distance


func _on_physics_frame() -> void:
	if _pending_build:
		_pending_build = false
		_build()
		return
	_ticks += 1
	if not is_instance_valid(_drone):
		_record()
		return

	# Drive the sled. Velocity rather than position, so the enemies' lead
	# solution reads a real closing speed.
	_drone.linear_velocity = _direction * _speed
	var at: Vector3 = _drone.global_position
	_drone.global_position = Vector3(at.x, ARENA_CENTER.y + ALTITUDE, at.z)
	var distance: float = at.distance_to(ARENA_CENTER)
	var band: int = int(distance / BAND_M)

	# The engage gate, decomposed. This is the half that tells "shoots and
	# misses" from "never shoots", and it is read per firer per frame.
	var engaging: bool = false
	for i: int in _firers.size():
		var firer: Node = _firers[i]
		if not is_instance_valid(firer):
			continue
		_firer_frames += 1
		var config: EnemyConfig = firer.get(&"enemy_config")
		var from: Vector3 = (firer as Node3D).global_position
		if from.distance_to(at) > config.sight_range:
			_out_of_range_frames += 1
		elif not _sees(firer, at):
			_no_los_frames += 1
		else:
			_engaged_frames += 1
			_engaged_by_type[config.type_id] = 					int(_engaged_by_type.get(config.type_id, 0)) + 1
			engaging = true
		# A SHOT IS A COOLDOWN THAT WENT UP. Both EnemyDrone and Turret set
		# `_cooldown = 1.0 / fire_rate` at the instant they fire and decay it
		# every frame, so a rise is a discharge and needs no production hook.
		var cooldown: float = float(firer.get(&"_cooldown"))
		if cooldown > _cooldowns[i] + 0.0001:
			_shots_total += 1
			_shots[band] = int(_shots.get(band, 0)) + 1
			# BY TYPE, because A.q7 asks whether the FALX already does this job.
			# It is the one type held on open approaches (LAYERING) and the only
			# one fast enough to chase - 25 m/s against a raider's 14 - so "who
			# fired" is the question, not just "how many".
			var type_id: StringName = config.type_id
			_shots_by_type[type_id] = int(_shots_by_type.get(type_id, 0)) + 1
			if _first_shot_m < 0.0:
				_first_shot_m = distance
		_cooldowns[i] = cooldown
	if engaging:
		_frames_engaged += 1

	_track_misses(at)

	# A gnat body that vanished is a sting that landed. The sled never fires, so
	# nothing else can remove one.
	for i: int in _stingers.size():
		var stinger: Node = _stingers[i]
		var alive: int = _living_bodies(stinger) if is_instance_valid(stinger) else 0
		if alive < _sting_bodies[i]:
			var stings: int = _sting_bodies[i] - alive
			_contact_hits += stings
			var config: EnemyConfig = stinger.get(&"enemy_config") \
					if is_instance_valid(stinger) else null
			if config != null:
				_contact_damage += config.damage * float(stings)
		_sting_bodies[i] = alive

	if distance <= ARRIVAL_M or _ticks > int(MAX_SECONDS * 240.0):
		_record()


func _record() -> void:
	var cell: Dictionary = _cells[_cell_i]
	_results.append({
		"name": cell["name"],
		"node": cell["node"],
		"speed": float(cell["speed"]),
		"firers": _firers.size(),
		"stingers": _stingers.size(),
		"shots": _shots_total,
		"hits": _hits_total,
		"contact_hits": _contact_hits,
		"contact_damage": _contact_damage,
		"ranged_hits": maxi(_hits_total - _contact_hits, 0),
		"ranged_damage": maxf(_damage_total - _contact_damage, 0.0),
		"damage": _damage_total,
		"seconds": float(_ticks) / 240.0,
		"first_shot_m": _first_shot_m,
		"first_hit_m": _first_hit_m,
		"misses": _misses.duplicate(),
		"shots_by_type": _shots_by_type.duplicate(),
		"engaged_by_type": _engaged_by_type.duplicate(),
		"placed_by_type": _placed_by_type.duplicate(),
		"shot_bands": _shots.duplicate(),
		"hit_bands": _hits.duplicate(),
		"firer_frames": _firer_frames,
		"out_of_range": _out_of_range_frames,
		"no_los": _no_los_frames,
		"engaged": _engaged_frames,
	})
	print("[approach]   %-30s %4.0f m/s  %2d guns  shots %4d  ranged hits %3d  contact %3d  %.0f dmg  first shot %s"
			% [cell["name"], float(cell["speed"]), _firers.size(), _shots_total,
			maxi(_hits_total - _contact_hits, 0), _contact_hits, _damage_total,
			"never" if _first_shot_m < 0.0 else "%.0f m" % _first_shot_m])
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_cell_i += 1
	if _cell_i >= _cells.size():
		_report()
		return
	_pending_build = true


## Line of sight, computed the way the firer computes it: the ray must reach the
## PLAYER and not something in between. Duplicated rather than called, because
## `_has_line_of_sight` takes no argument and reads the firer's own `_player`,
## and a bench that called it would be asserting the function with itself.
func _sees(firer: Node, at: Vector3) -> bool:
	var from: Vector3 = (firer as Node3D).global_position
	var query := PhysicsRayQueryParameters3D.create(from, at)
	query.exclude = [(firer as CollisionObject3D).get_rid()]
	var hit: Dictionary = _arena.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == _drone


## ---------- the report ----------

func _report() -> void:
	print("")
	print("[approach] ---- THE UNCONTESTED APPROACH (A.q7), theater %d ----" % _seed)
	print("[approach] `hit%` is RANGED hits over shots. Contact stings are a")
	print("[approach] separate column because they are a different mechanism:")
	print("[approach] a gnat reaching you is not a gun landing a round, and the")
	print("[approach] first version of this bench fused them into a 250% hit rate.")
	print("[approach] %-30s %6s %6s %6s %7s %8s %8s %9s"
			% ["cell", "m/s", "shots", "hits", "hit%", "contact", "dmg", "1st shot"])
	for r: Dictionary in _results:
		var rate: String = "   n/a"
		if int(r["shots"]) > 0:
			rate = "%5.0f%%" % (float(r["ranged_hits"]) / float(r["shots"]) * 100.0)
		print("[approach] %-30s %6.0f %6d %6d %7s %8d %8.0f %9s"
				% [r["name"], float(r["speed"]), int(r["shots"]),
				int(r["ranged_hits"]), rate, int(r["contact_hits"]),
				float(r["damage"]),
				"never" if float(r["first_shot_m"]) < 0.0
						else "%.0f m" % float(r["first_shot_m"])])

	print("")
	print("[approach] ---- the engage gate, as firer-frames ----")
	print("[approach] this is what separates 'shoots and misses' from 'never shoots'.")
	for r: Dictionary in _results:
		var total: float = maxf(float(r["firer_frames"]), 1.0)
		print("[approach]   %-30s %4.0f m/s  out of range %3.0f%%  no line of sight %3.0f%%  ENGAGED %3.0f%%"
				% [r["name"], float(r["speed"]),
				float(r["out_of_range"]) / total * 100.0,
				float(r["no_los"]) / total * 100.0,
				float(r["engaged"]) / total * 100.0])

	print("")
	print("[approach] ---- shots and hits by distance from the centre ----")
	for r: Dictionary in _results:
		var shot_bands: Dictionary = r["shot_bands"]
		var hit_bands: Dictionary = r["hit_bands"]
		var keys: Array = shot_bands.keys()
		for key: int in hit_bands:
			if not keys.has(key):
				keys.append(key)
		keys.sort()
		keys.reverse()
		var pieces: PackedStringArray = []
		for band: int in keys:
			pieces.append("%d-%d m: %d shot / %d hit"
					% [band * int(BAND_M), (band + 1) * int(BAND_M),
					int(shot_bands.get(band, 0)), int(hit_bands.get(band, 0))])
		print("[approach]   %-30s %4.0f m/s  %s"
				% [r["name"], float(r["speed"]),
				" | ".join(pieces) if not pieces.is_empty() else "nothing fired"])

	_print_misses()
	_print_by_type()
	_print_speed_curve()
	print("")
	print("[approach] NOTHING HERE LICENSES A TUNING CHANGE (H6). It is a reading.")
	quit()


## HOW FAR DO THEY MISS BY? The number that decides what kind of problem this is.
func _print_misses() -> void:
	print("")
	print("[approach] ---- how close the rounds came, by speed ----")
	print("[approach] closest approach of each enemy round to the drone.")
	var by_speed: Dictionary = {}
	for r: Dictionary in _results:
		var speed: float = float(r["speed"])
		if not by_speed.has(speed):
			by_speed[speed] = []
		(by_speed[speed] as Array).append_array(r["misses"])
	var speeds: Array = by_speed.keys()
	speeds.sort()
	for speed: float in speeds:
		var misses: Array = by_speed[speed]
		if misses.is_empty():
			print("[approach]   %4.0f m/s: no rounds tracked" % speed)
			continue
		misses.sort()
		var median: float = float(misses[misses.size() / 2])
		var within_2: int = 0
		var within_5: int = 0
		for m: float in misses:
			if m <= 2.0:
				within_2 += 1
			if m <= 5.0:
				within_5 += 1
		print("[approach]   %4.0f m/s: %3d rounds, median miss %5.1f m, closest %4.1f m, within 2 m: %2d (%2.0f%%), within 5 m: %2d (%2.0f%%)"
				% [speed, misses.size(), median, float(misses[0]),
				within_2, float(within_2) / float(misses.size()) * 100.0,
				within_5, float(within_5) / float(misses.size()) * 100.0])


## A.q7 ASKED DIRECTLY: does the falx already contest the approach?
##
## LAYERING holds the falx on the outer ring because it is the one type designed
## for an open approach, and its config is 25 m/s against a raider's 14 - the only
## body in the roster that can stay with a quad on an ingress run. So the honest
## way to answer "do we need something new" is to ask what the thing we already
## have actually did, per type, at each speed.
func _print_by_type() -> void:
	print("")
	print("[approach] ---- WHO contests the approach, by bestiary type ----")
	var by_type: Dictionary = {}
	for r: Dictionary in _results:
		var speed: float = float(r["speed"])
		for type_id: StringName in r["placed_by_type"]:
			var key: String = "%s @ %.0f" % [type_id, speed]
			if not by_type.has(key):
				by_type[key] = {"type": type_id, "speed": speed, "placed": 0,
						"shots": 0, "engaged": 0}
			by_type[key]["placed"] = int(by_type[key]["placed"]) 					+ int(r["placed_by_type"][type_id])
			by_type[key]["shots"] = int(by_type[key]["shots"]) 					+ int(r["shots_by_type"].get(type_id, 0))
			by_type[key]["engaged"] = int(by_type[key]["engaged"]) 					+ int(r["engaged_by_type"].get(type_id, 0))
	var keys: Array = by_type.keys()
	keys.sort()
	for key: String in keys:
		var row: Dictionary = by_type[key]
		print("[approach]   %-10s at %4.0f m/s: %2d placed, %4d shots, %5d engaged-frames"
				% [row["type"], float(row["speed"]), int(row["placed"]),
				int(row["shots"]), int(row["engaged"])])


## The whole point: does the garrison's ability to touch you fall off with speed?
func _print_speed_curve() -> void:
	print("")
	print("[approach] ---- by speed, across every cell ----")
	var by_speed: Dictionary = {}
	for r: Dictionary in _results:
		var speed: float = float(r["speed"])
		if not by_speed.has(speed):
			by_speed[speed] = {"shots": 0, "hits": 0, "damage": 0.0, "cells": 0,
					"engaged": 0, "frames": 0}
		by_speed[speed]["shots"] = int(by_speed[speed]["shots"]) + int(r["shots"])
		by_speed[speed]["hits"] = int(by_speed[speed]["hits"]) + int(r["ranged_hits"])
		by_speed[speed]["contact"] = int(by_speed[speed].get("contact", 0)) \
				+ int(r["contact_hits"])
		by_speed[speed]["damage"] = float(by_speed[speed]["damage"]) \
				+ float(r["ranged_damage"])
		by_speed[speed]["cells"] = int(by_speed[speed]["cells"]) + 1
		by_speed[speed]["engaged"] = int(by_speed[speed]["engaged"]) + int(r["engaged"])
		by_speed[speed]["frames"] = int(by_speed[speed]["frames"]) + int(r["firer_frames"])
	var speeds: Array = by_speed.keys()
	speeds.sort()
	for speed: float in speeds:
		var row: Dictionary = by_speed[speed]
		var shots: int = int(row["shots"])
		var rate: String = "n/a"
		if shots > 0:
			rate = "%.0f%%" % (float(row["hits"]) / float(shots) * 100.0)
		print("[approach]   %4.0f m/s: %5d shots, %4d ranged hits (%s), %5.0f ranged damage, %3d contact stings, engaged %2.0f%% of gun-frames, %d cells"
				% [speed, shots, int(row["hits"]), rate, float(row["damage"]),
				int(row.get("contact", 0)),
				float(row["engaged"]) / maxf(float(row["frames"]), 1.0) * 100.0,
				int(row["cells"])])
	print("[approach] a Kestrel's hull is %.0f. Read `damage` against that."
			% Frames.build(Frames.KESTREL).frame.hull)
