class_name SortieRunner
extends Node

## THE BRIDGE (GAMEPLAY-DESIGN Iteration 12). Takes a `sortie_spec` from
## `SortieComposer` and builds the fight it describes.
##
## This is the function the project has been missing. Every pillar was designed
## and four of the five were built: the theater generates, the sim ticks, the
## manifest dresses a garrison in named units, and the composer turns a node
## into a complete spec — archetype, objective, layered garrison, triggered
## reserves, approach, pads, dares. `compose()` was called by nothing but its
## own tests, so the campaign and the game had never met.
##
## WHAT THIS IS NOT. It is not a second wave director, and the difference is
## the whole point of W2. `WaveDirector` counts a budget and spawns a ring; a
## sortie PLACES a garrison in concentric layers around something you have to
## destroy, and holds part of it back to arrive because of a decision you made.
## A dogfight spec collapses to one flat layer with reserves that trigger on
## `wave_cleared`, which is the wave director's shape — that is deliberate
## (P2.12 demotes it to one archetype) and it is why the dogfight is the cheap
## proof the pipe connects rather than the destination.
##
## PURE INPUT, DIRTY OUTPUT. The spec is a plain serializable Dictionary and
## nothing upstream of here knows what a Node3D is. This file is the only place
## that translation happens, which is what keeps the war deterministic and
## replayable (F4) while the fight is full of physics.

## A unit reached the field, left it, or the sortie changed phase.
signal announced(text: String)
signal enemy_destroyed(points: float)
## The objective is down and the way home is open (W.q3: a Strike ends on
## EGRESS, not on the objective's death).
signal egress_opened
## Everything is over. `result` is the serializable outcome the war eats.
signal sortie_finished(result: Dictionary)

enum Phase { IDLE, ENGAGED, EGRESS, DONE }

## Concentric placement (P2.3). Reading the layers IS reading your ingress
## (P2.4), so they have to be far enough apart to read as separate rings from
## the air rather than as one cloud at three radii.
const LAYER_RADIUS: Dictionary = {
	&"inner": 26.0, &"mid": 48.0, &"outer": 74.0,
}
## Jitter so a ring is a ring and not a parade formation.
const LAYER_JITTER: float = 9.0
const AIR_HEIGHT_MIN: float = 7.0
const AIR_HEIGHT_MAX: float = 20.0
## A ground unit sits on whatever is under it, probed from here down. Borrowed
## from the wave director for the reason it was written there: a rooftop
## emplacement is a good outcome and a turret buried in a building is not.
const GROUND_PROBE_HEIGHT: float = 60.0
## The bomber's run ends over the middle, above the greybox skyline.
const BOMB_RUN_HEIGHT: float = 26.0

## Where the objective's structures sit relative to the sortie's centre.
const OBJECTIVE_SPREAD: float = 13.0

## How far back out you have to get for an egress to count. Comfortably past
## the outer ring, so leaving means actually leaving rather than drifting to
## the edge of the fight.
const EGRESS_RADIUS: float = 105.0

## The sortie's centre in world space. NOT a const, and that is W9.2's finding
## made structural: `WaveDirector.ARENA_CENTER` is a constant because the
## greybox has exactly one piece of usable air, and anything that reads its
## centre from a const can never host a generated map.
@export var center := Vector3.ZERO

var phase: int = Phase.IDLE
var spec: Dictionary = {}

## Live units, and the bookkeeping the outcome is priced from.
var units: Array[Node] = []
var objectives: Array[ObjectiveAsset] = []
## type_id -> BODIES killed. What `WarManifest.dent_from_kills` eats, and the
## reason a half-cleared gnat pack dents by half a pack rather than by nothing.
var kills: Dictionary = {}

var _rng := RandomNumberGenerator.new()
## Reserve payloads, and a parallel spent-flag. Deliberately NOT a Dictionary
## keyed by the trigger dict: Godot hashes a Dictionary by content, so two
## structurally identical waves would collide into one key and the second would
## silently never fire.
var _triggers: Array[Dictionary] = []
var _trigger_spent: Array[bool] = []
var _objectives_down: int = 0
var _egressed: bool = false
var _pilot_lost: bool = false
var _player: Node3D


## Build the fight this spec describes. `player` is watched for the egress
## test; pass null headless and drive the ending with `force_egress()`.
func start(sortie_spec: Dictionary, player: Node3D = null) -> void:
	spec = sortie_spec
	_player = player
	_rng.seed = int(spec.get("seed", 0))
	kills.clear()
	units.clear()
	objectives.clear()
	_triggers.clear()
	_trigger_spent.clear()
	_objectives_down = 0
	_egressed = false
	_pilot_lost = false

	for trigger: Dictionary in spec.get("triggers", []):
		_triggers.append(trigger)
		_trigger_spent.append(false)

	_spawn_objectives()
	_place_layers()
	phase = Phase.ENGAGED
	announced.emit("%s - %s" % [String(spec["archetype"]).to_upper(),
			String(spec["objective"]).replace("_", " ")])
	set_physics_process(true)


## Units still up. UNITS, not bodies (P4.q5) — a gnat cloud is one.
func remaining() -> int:
	return units.size()


## Reserves that have not been released yet.
func reserves_held() -> int:
	var held: int = 0
	for spent: bool in _trigger_spent:
		if not spent:
			held += 1
	return held


## Does this spec have a structure to destroy, or IS the garrison the objective?
func has_objective() -> bool:
	return int(spec.get("objective_assets", 0)) > 0


## The outcome the war-sim eats, and it is a SPECTRUM (P2.9 / P2.q4: every kill
## dents the node, so a death is a partial rather than a waste).
func result() -> Dictionary:
	var total: int = int(spec.get("objective_assets", 0))
	var complete: bool = _objectives_down >= total if total > 0 \
			else units.is_empty() and reserves_held() == 0
	return {
		"node_id": int(spec.get("node_id", -1)),
		"seed": int(spec.get("seed", 0)),
		"archetype": spec.get("archetype", &"dogfight"),
		"objective_assets": total,
		"objectives_destroyed": _objectives_down,
		# The capture GATE (P2.9). A dogfight has no structure, so clearing the
		# field IS its objective; a strike has to actually flatten the thing.
		"objective_complete": complete,
		"egressed": _egressed,
		"pilot_lost": _pilot_lost,
		# The three-way spectrum P2.9 asks for, as one readable field. `complete`
		# needs the egress too: getting the objective and not getting home is a
		# genuinely different outcome from both, and the war can price it.
		"outcome": &"lost" if _pilot_lost \
				else (&"complete" if complete and _egressed else &"partial"),
		"kills": kills.duplicate(),
		# The exchange rate, finally paying out: kinetic result -> war currency.
		"dent": WarManifest.dent_from_kills(kills),
	}


## Headless hook, and the manual way out for anything without a player body.
func force_egress() -> void:
	if phase != Phase.EGRESS:
		return
	_egressed = true
	_finish()


## The pilot died, or the sortie was given up on.
##
## THIS EXISTS BECAUSE P2.q4 WOULD OTHERWISE BE A LIE. Without it a sortie only
## ever finished by egressing, so a pilot who died three structures deep emitted
## nothing, the war never heard about any of it, and "every kill dents the node"
## quietly meant "every kill on a sortie you survived". A death is the case the
## no-wasted-sortie rule was written FOR.
func abort(reason: String = "pilot down") -> void:
	if phase == Phase.DONE or phase == Phase.IDLE:
		return
	_pilot_lost = true
	announced.emit(reason)
	_finish()


func _physics_process(_delta: float) -> void:
	if phase != Phase.EGRESS or _player == null or not is_instance_valid(_player):
		return
	if _player.global_position.distance_to(center) >= EGRESS_RADIUS:
		_egressed = true
		_finish()


## ---------- placement ----------

func _spawn_objectives() -> void:
	var count: int = int(spec.get("objective_assets", 0))
	for i: int in count:
		# Spread on a ring so three assets are three separate runs rather than
		# one wall you can hose from a single position.
		var angle: float = TAU * float(i) / float(count) + _rng.randf_range(-0.2, 0.2)
		var asset := ObjectiveAsset.new()
		asset.position = center + Vector3(
				cos(angle) * OBJECTIVE_SPREAD, 0.0, sin(angle) * OBJECTIVE_SPREAD)
		get_parent().add_child(asset)
		objectives.append(asset)
		asset.destroyed.connect(_on_objective_destroyed)
		asset.first_damaged.connect(_on_objective_damaged)


func _place_layers() -> void:
	for layer: StringName in SortieComposer.LAYER_ORDER:
		for unit: Dictionary in spec["layers"][layer]:
			for i: int in int(unit["count"]):
				_spawn_unit(unit["type"], layer)


func _spawn_unit(type_id: StringName, layer: StringName) -> void:
	if not WaveDirector.ROSTER.has(type_id):
		push_warning("[sortie] spec names unknown type %s" % type_id)
		return
	var row: Dictionary = WaveDirector.ROSTER[type_id]
	var unit: Node = (load(row["scene"]) as PackedScene).instantiate()
	# Positioned BEFORE entering the tree, because every type reads its own
	# position in _ready to build its patrol, pack or wander home. The wave
	# director learned this the hard way: every wave raider in the game's
	# history wandered home to the origin until v1.85 caught it.
	(unit as Node3D).position = _point_for(row, layer)
	if unit.get(&"route_end") != null:
		unit.set(&"route_end", center + Vector3.UP * BOMB_RUN_HEIGHT)
	# A body that comes back makes its sortie permanently unclearable.
	if unit.get(&"respawns") != null:
		unit.set(&"respawns", false)
	get_parent().add_child(unit)
	units.append(unit)
	unit.connect(&"destroyed", _on_points_scored.bind(type_id))
	# The UNIT is over when the unit is over: a cloud says so with `cleared`, a
	# single body says so by dying, and a bomber that got through says so with
	# `detonated` — opposite outcome, identical bookkeeping.
	if (unit as Object).has_signal(&"cleared"):
		unit.connect(&"cleared", _on_unit_gone.bind(unit))
	else:
		unit.connect(&"destroyed", func(_p: float) -> void: _on_unit_gone(unit))
	if (unit as Object).has_signal(&"detonated"):
		unit.connect(&"detonated", func() -> void:
			announced.emit("bomber reached its target")
			_on_unit_gone(unit))


func _point_for(row: Dictionary, layer: StringName) -> Vector3:
	var radius: float = maxf(float(LAYER_RADIUS.get(layer, 60.0))
			+ _rng.randf_range(-LAYER_JITTER, LAYER_JITTER), 8.0)
	var angle: float = _rng.randf_range(0.0, TAU)
	var at: Vector3 = center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	if bool(row["ground"]):
		return _seat_on_ground(at)
	at.y = float(row.get("height", -1.0))
	if at.y < 0.0:
		at.y = _rng.randf_range(AIR_HEIGHT_MIN, AIR_HEIGHT_MAX)
	return at


func _seat_on_ground(at: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_tree().root.world_3d.direct_space_state
	if space == null:
		return at
	var query := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * GROUND_PROBE_HEIGHT, at + Vector3.DOWN * 5.0)
	var hit: Dictionary = space.intersect_ray(query)
	# Only solid scenery seats an emplacement; a flyer overhead is traffic.
	if not hit.is_empty() and hit["collider"] is StaticBody3D:
		return hit["position"]
	return at


## ---------- triggers (W6) ----------

## Reserves arrive because of something you DID. That is the whole mechanical
## difference between a wave and a sortie: a wave arrives because the last one
## died. Deterministic responses only (P2.q3) — replayability and an honest
## harness demand it, and it is what makes staying unseen real counterplay.
##
## Fires exactly ONE trigger per event, the lowest unspent wave number matching
## it. A dogfight holds two waves both keyed `wave_cleared`, and releasing both
## on the first clear would collapse the archetype's pacing into a single dump.
func _fire_trigger(on: StringName) -> void:
	var pick: int = -1
	for i: int in _triggers.size():
		if _trigger_spent[i] or _triggers[i]["on"] != on:
			continue
		if pick < 0 or int(_triggers[i].get("wave", 1)) < int(_triggers[pick].get("wave", 1)):
			pick = i
	if pick < 0:
		return
	_trigger_spent[pick] = true
	var payload: Dictionary = _triggers[pick]
	announced.emit("contact - reserves inbound")
	get_tree().create_timer(float(payload.get("after_s", 0.0))).timeout.connect(
			func() -> void: _release(payload))


func _release(trigger: Dictionary) -> void:
	if phase == Phase.DONE:
		return
	for unit: Dictionary in trigger["units"]:
		for i: int in int(unit["count"]):
			# Reserves come in from outside the outer ring: they are ARRIVING,
			# not materialising on top of you.
			_spawn_unit(unit["type"], &"outer")
	_check_field_cleared()


## ---------- outcomes ----------

func _on_points_scored(points: float, type_id: StringName) -> void:
	# BODIES, not units: a gnat is worth its points and its dent even though
	# nine of them are one unit.
	kills[type_id] = int(kills.get(type_id, 0)) + 1
	enemy_destroyed.emit(points)


func _on_unit_gone(unit: Node) -> void:
	if not units.has(unit):
		return
	units.erase(unit)
	if not units.is_empty():
		return
	_fire_trigger(&"wave_cleared")
	_check_field_cleared()


## A DOGFIGHT has no structure to flatten, so clearing the field is its
## objective (ARCHETYPES gives it `assets: 0`). Without this a dogfight could
## never finish, which is exactly the deadlock `composition_check` exists to
## catch one level down.
func _check_field_cleared() -> void:
	if phase != Phase.ENGAGED or has_objective():
		return
	if not units.is_empty() or reserves_held() > 0:
		return
	_open_egress("AIRSPACE CLEAR - get out")


func _on_objective_damaged() -> void:
	_fire_trigger(&"objective_damaged")


func _on_objective_destroyed(points: float) -> void:
	_objectives_down += 1
	enemy_destroyed.emit(points)
	var total: int = int(spec.get("objective_assets", 0))
	announced.emit("objective %d of %d down" % [_objectives_down, total])
	if _objectives_down >= total:
		_open_egress("OBJECTIVE COMPLETE - get out")


func _open_egress(text: String) -> void:
	if phase != Phase.ENGAGED:
		return
	phase = Phase.EGRESS
	announced.emit(text)
	egress_opened.emit()


func _finish() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	set_physics_process(false)
	sortie_finished.emit(result())
