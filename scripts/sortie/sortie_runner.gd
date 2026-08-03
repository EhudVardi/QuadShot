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

## PADS (P2.6, W.q4). `spec["pads"]` has been emitted since v1.71 with nothing
## in the project consuming it, and Iteration 10 then built the hardware for it
## by accident while solving a different problem. This is where the two meet.
##
## THE ORDER IS THE DESIGN: the first pad is always the REPAIR gate, and only
## then do resupply gates alternate flak/missile. Hull is the resource you
## cannot fly without — a pilot out of missiles is inconvenienced, a pilot out
## of hull is dead — so a node generous enough for exactly one pad should hand
## you the green one. Confirmed the hard way on the first hand-flown strike: a
## zero-pad node meant flying a broken drone the whole way, which is P2.6
## working rather than a gap.
##
## They ring between the inner and mid layers, so a pad is a DETOUR INTO the
## fight rather than a trip to the edge of the map — the wave director's
## reasoning for its own gates, and it applies harder here because the objective
## is at the centre.
const PAD_RADIUS_MIN: float = 30.0
const PAD_RADIUS_MAX: float = 44.0
const PAD_HEIGHT_MIN: float = 5.0
const PAD_HEIGHT_MAX: float = 14.0
const PAD_MIN_SEPARATION: float = 16.0
## Clear space a pad needs from scenery, and separately from an objective
## structure (which is 7 m across and 9 m tall, so it needs more room).
const PAD_CLEARANCE: float = 3.4
const PAD_OBJECTIVE_CLEARANCE: float = 14.0
const PAD_PLACE_TRIES: int = 40

## How far back out you have to get for an egress to count. Comfortably past
## the outer ring, so leaving means actually leaving rather than drifting to
## the edge of the fight.
const EGRESS_RADIUS: float = 105.0

## ---------- THE INGRESS (Iteration 14 / A6, and W.q7 answered by building) ----
##
## THE PILOT STARTS OUTSIDE THE TARGET AREA, on the bearing the spec already
## carries, and flies their own approach.
##
## WHAT IT REPLACES, and why the replacement is not an addition. Until now
## `sortie.tscn` left the drone wherever the scene file parked it, which was the
## middle of the arena — INSIDE the concentric rings, with a garrison arranged to
## face outward at nothing. That is the whole of the user's *"some sorties seem
## open, but when I fly into them nothing engages with me"*: `EnemyDrone` engages
## on its distance to the PLAYER, so a pilot sitting at the centre was outside
## every ring's sight range at once, and the rings the composer had carefully
## layered were all pointing the wrong way.
##
## v2.12's `SIGHT_COVERAGE` clamp was a compensation for exactly that — pull each
## defender inward until it can see the centre the pilot was standing on — and it
## is DELETED here rather than kept beside the ingress. An A/B against
## `sortie_bench`, which has always spawned outside and flown in, showed the clamp
## made no measurable difference to an approaching pilot: node 12 read `best flak
## 0% (dent 9.7)` clamped and unclamped, identical to one decimal. Two mechanisms
## for one problem, where the second one is the real fix, is how a compensation
## quietly becomes a rule nobody can delete later.
##
## THE SCALE CHANGE IS THE ONE THING HERE THAT IS NOT A DIRECT READING OF THE
## SPEC, and it is deliberate. `SortieComposer` emits `ingress_m` in FICTION
## units — 400 m over open desert down to 150 m through a city — and it is right
## to, because `war/` is pure and cannot know how much air any particular arena
## has. This one has about 100 m of ground in each direction and an FPV link that
## drops at 300 m, so a 400 m spawn would put the pilot over the void with the
## video already gone. The runner is the only place a spec becomes a Node3D, so
## the runner is where fiction units become world units: the composer's own band
## is remapped onto the band this arena can host, ORDER PRESERVED. Open ground
## still buys the longest exposed run and a city still drops you closest.
##
## THE TWO NUMBERS IT HAS TO SIT BETWEEN, both asserted by `sortie_check`:
##   - above `EGRESS_RADIUS` (105 m) by a clear margin, or the pilot spawns on
##     the far side of the line a strike ends by crossing;
##   - below the FPV link's warning radius (220 m in `sortie.gd`), or the game
##     tells you the signal is weak before you have moved.
const INGRESS_MIN_M: float = 140.0
const INGRESS_MAX_M: float = 195.0
## The pilot launches from the deck rather than from a hover. Taking off is a
## beat, and A6's open-field fiction — *"fly low to avoid SAM sites, until he
## gets close"* — wants low to be where you START, not somewhere you descend to.
## Matches the height the scene parks the drone at over its spawn pad.
const INGRESS_ALTITUDE_M: float = 0.8

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
## This sortie's repair and resupply gates (P2.6's pads, W.q4).
var pads: Array[Node3D] = []
## type_id -> BODIES killed. What `WarManifest.dent_from_kills` eats, and the
## reason a half-cleared gnat pack dents by half a pack rather than by nothing.
var kills: Dictionary = {}

var _rng := RandomNumberGenerator.new()
## Reserve payloads, and two parallel flags. Deliberately NOT a Dictionary keyed
## by the trigger dict: Godot hashes a Dictionary by content, so two structurally
## identical waves would collide into one key and the second would silently never
## fire.
##
## FIRED AND ARRIVED ARE DIFFERENT THINGS, and collapsing them into one flag was
## a real bug. `_fire_trigger` starts a timer and marks the reserve spent so it
## cannot fire twice; the units do not exist until `after_s` later. A dogfight
## holds two `wave_cleared` reserves at 1.5 s and 3.5 s, so on the second clear
## the field was empty, every trigger was "spent", and the sortie announced
## AIRSPACE CLEAR in the same frame it announced reserves inbound - with a whole
## wave the composer had taken OUT of the garrison (P2.3) still on a timer. Worse
## than the contradiction: leaving promptly scored `complete` while staying to
## fight the wave scored `partial`, so the sortie paid you to fly away from the
## fight it had just started. `_trigger_spent` answers "can this fire again";
## `_trigger_released` answers "is this reserve still coming", and only the second
## one may gate an egress.
var _triggers: Array[Dictionary] = []
var _trigger_spent: Array[bool] = []
var _trigger_released: Array[bool] = []
## Collision RIDs of bodies freed by this start() call. They outlive the call by
## one frame (queue_free is deferred), so pad placement has to exclude them.
var _stale_rids: Array[RID] = []
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
	# EVERYTHING the last sortie built goes, not just the pads. Clearing the
	# arrays without freeing the bodies left the previous sortie's units and
	# structures in the parent tree with their signals still connected, so a stale
	# objective could open the NEW sortie's egress and a stale kill was credited to
	# the new node's dent. `sortie_check` papered over it by sweeping the arena
	# itself - the caller compensating for the callee, which is how the same
	# deferred-free trap then reached the check.
	#
	# THE RIDS ARE KEPT because `queue_free` is DEFERRED. Everything freed here is
	# still a solid body in the physics space for the rest of this frame, and
	# `_lay_pads()` runs its rejection sampling four lines below - so the new
	# sortie's pads get rejected by the ghosts of the old one, and a pad that fails
	# to place is a pad the pilot does not get. Same trap, same frame, as the
	# intermittent `ammo_check` failure that took two sessions to catch; the fix is
	# the same one (`seen_gates`), applied at the source this time.
	_stale_rids.clear()
	for unit: Node in units:
		if is_instance_valid(unit):
			_remember_rid(unit)
			unit.queue_free()
	units.clear()
	for asset: ObjectiveAsset in objectives:
		if is_instance_valid(asset):
			_remember_rid(asset)
			asset.queue_free()
	objectives.clear()
	for pad: Node3D in pads:
		if is_instance_valid(pad):
			_remember_rid(pad)
			pad.queue_free()
	pads.clear()
	_triggers.clear()
	_trigger_spent.clear()
	_trigger_released.clear()
	_objectives_down = 0
	_egressed = false
	_pilot_lost = false

	for trigger: Dictionary in spec.get("triggers", []):
		_triggers.append(trigger)
		_trigger_spent.append(false)
		_trigger_released.append(false)

	_spawn_objectives()
	_lay_pads()
	_place_layers()
	phase = Phase.ENGAGED
	announced.emit("%s - %s" % [String(spec["archetype"]).to_upper(),
			String(spec["objective"]).replace("_", " ")])
	set_physics_process(true)


## Units still up. UNITS, not bodies (P4.q5) — a gnat cloud is one.
func remaining() -> int:
	return units.size()


## Reserves that have not ARRIVED yet - including one already on its timer.
## This is what may gate an egress: a wave that is inbound is a wave you still
## have to meet, and reading the spent flag here declared the airspace clear
## while it was in the air.
func reserves_held() -> int:
	var held: int = 0
	for released: bool in _trigger_released:
		if not released:
			held += 1
	return held


## Reserves that can still be triggered by an event. Separate from the above so
## a caller can tell "nothing left to summon" from "nothing left to fight".
func reserves_unfired() -> int:
	var unfired: int = 0
	for spent: bool in _trigger_spent:
		if not spent:
			unfired += 1
	return unfired


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


## ---------- placement: the pilot (A6) ----------

## Compass direction of the ingress point AS SEEN FROM THE TARGET. 0 deg is -Z
## and it increases clockwise, so `bearing_deg` reads like a bearing on a map
## rather than like a Godot angle, and "ingress from the SE" means the pilot is
## south-east of what they came to hit.
##
## Static and pure, all four of these: they are called BEFORE `start()` — the
## pilot has to be standing at the ingress while they read the briefing, not
## teleported there when they arm — and a headless check has to be able to assert
## the geometry without an arena.
static func ingress_direction(spec: Dictionary) -> Vector3:
	var approach: Dictionary = spec.get("approach", {})
	var bearing: float = deg_to_rad(float(approach.get("bearing_deg", 0.0)))
	return Vector3(sin(bearing), 0.0, -cos(bearing))


## How far out that is IN THIS ARENA. See the header for why this is a remap of
## `ingress_m` rather than the number itself, and why the remap lives here.
static func ingress_range(spec: Dictionary) -> float:
	var approach: Dictionary = spec.get("approach", {})
	var fiction: float = float(approach.get("ingress_m", SortieComposer.INGRESS_OPEN_M))
	# The composer's own band, read off the composer, so the two cannot drift: a
	# hard-coded [150, 400] here would silently start clipping the day a biome's
	# cover economics changed.
	var shortest: float = SortieComposer.INGRESS_OPEN_M - SortieComposer.INGRESS_COVER_M
	var t: float = clampf(
			inverse_lerp(shortest, SortieComposer.INGRESS_OPEN_M, fiction), 0.0, 1.0)
	return lerpf(INGRESS_MIN_M, INGRESS_MAX_M, t)


## Where the pilot starts. A transform rather than a point, because FACING THE
## TARGET is most of what makes an approach readable from the cockpit: the whole
## instruction becomes "it is that way, go", and every other decision — how low,
## how fast, which side — is left to the pilot, which is the point of P2.4.
static func ingress_transform(spec: Dictionary, at_center: Vector3) -> Transform3D:
	var direction: Vector3 = ingress_direction(spec)
	var origin: Vector3 = at_center + direction * ingress_range(spec)
	origin.y = at_center.y + INGRESS_ALTITUDE_M
	# Drone front is body -Z (the pilot-axis convention), and `Basis.looking_at`
	# aims -Z at what it is given — so the target direction is -direction, back
	# down the bearing toward the middle.
	return Transform3D(Basis.looking_at(-direction, Vector3.UP), origin)


## The ingress for THIS runner's centre. The instance-side convenience, so a
## caller that already has a runner does not have to know where its centre lives.
func ingress() -> Transform3D:
	return ingress_transform(spec, center)


## ---------- placement: the garrison ----------

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


## P2.6's difficulty knob, finally connected. A pad-rich node is survivable and
## a pad-poor one makes every hit count, and NEITHER is authored — the composer
## derives the count from the node's own garrison and the war's escalation, so
## "this target is brutal" is a fact about the war rather than a level setting.
func _lay_pads() -> void:
	var count: int = int(spec.get("pads", 0))
	var placed: Array[Vector3] = []
	for i: int in count:
		var at: Vector3 = _pad_point(placed)
		if at == Vector3.INF:
			# Failing to place is a fine outcome: one fewer pad is a slightly
			# harder sortie, where a pad buried in a building is a sortie that
			# lies to you.
			push_warning("[sortie] no clear spot for pad %d" % i)
			continue
		placed.append(at)
		var gate: Node3D
		if i == 0:
			gate = (load("res://scenes/combat/repair_gate.tscn") as PackedScene) \
					.instantiate() as Node3D
		else:
			var resupply := ResupplyGate.new()
			# Alternate starting with flak: the pod burns its magazine several
			# times faster than the rack does.
			resupply.kind = &"flak" if i % 2 == 1 else &"missile"
			gate = resupply
		gate.position = at
		get_parent().add_child(gate)
		# Faced at the objective, so the approach is a line you fly rather than
		# an angle you have to discover.
		var flat := Vector3(center.x - at.x, 0.0, center.z - at.z)
		if flat.length() > 0.1:
			gate.look_at(gate.global_position + flat, Vector3.UP)
		pads.append(gate)


## A spot for a pad that clears the other pads, the objective structures, and
## real scenery.
##
## The objective clearance is checked ARITHMETICALLY rather than with the shape
## cast, deliberately: the structures were added to the tree microseconds ago in
## the same call, and a body's collision shape is not registered with the
## physics space until the next physics step — so a cast would sail straight
## through them and cheerfully park a repair gate inside a factory.
func _pad_point(placed: Array[Vector3]) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_tree().root.world_3d.direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = PAD_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	for attempt: int in PAD_PLACE_TRIES:
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = _rng.randf_range(PAD_RADIUS_MIN, PAD_RADIUS_MAX)
		var at: Vector3 = center + Vector3(
				cos(angle) * radius,
				_rng.randf_range(PAD_HEIGHT_MIN, PAD_HEIGHT_MAX),
				sin(angle) * radius)
		var clear: bool = true
		for other: Vector3 in placed:
			if at.distance_to(other) < PAD_MIN_SEPARATION:
				clear = false
				break
		if not clear:
			continue
		for asset: ObjectiveAsset in objectives:
			if is_instance_valid(asset) \
					and at.distance_to(asset.position) < PAD_OBJECTIVE_CLEARANCE:
				clear = false
				break
		if not clear:
			continue
		if space != null:
			query.transform = Transform3D(Basis.IDENTITY, at)
			# The bodies this same call just queue_freed are still solid.
			query.exclude = _stale_rids
			# Static scenery only: a drifting raider is not a reason to reject a
			# spot that will be empty a second later.
			for hit: Dictionary in space.intersect_shape(query, 4):
				if hit["collider"] is StaticBody3D:
					clear = false
					break
		if clear:
			return at
	return Vector3.INF


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


## A unit sits on its own ring at a uniformly random angle, and BOTH halves of
## that are the ingress's doing.
##
## The ring is untouched because there is finally an approach for it to be
## arranged against: a mid-ring turret 57 m out cannot see the middle, and does
## not need to — with its 45 m sight it covers the annulus an arriving pilot has
## to cross, which is what a ring of area denial is FOR. The clamp that used to
## pull it inward (v2.12) was answering a pilot who started in the middle.
##
## The angle stays uniform because the garrison does not know which way you are
## coming from. Biasing the layers toward `bearing_deg` would be the enemy
## reading the player's spawn point, and it would delete the counterplay P2.3
## describes — pick your side, arrive unseen, and only the quadrant you crossed
## gets a vote.
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


## Every collision RID under `node`, itself included. A unit is often a container
## (a gnat cloud is one unit and many bodies), so a single get_rid() would leave
## most of a pack solid.
func _remember_rid(node: Node) -> void:
	if node is CollisionObject3D:
		_stale_rids.append((node as CollisionObject3D).get_rid())
	for child: Node in node.get_children():
		_remember_rid(child)


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
	announced.emit("contact - reserves inbound")
	# Bound by INDEX, not by payload: `_release` has to flip the released flag,
	# and two structurally identical waves are indistinguishable as dictionaries.
	get_tree().create_timer(float(_triggers[pick].get("after_s", 0.0))) \
			.timeout.connect(_release.bind(pick))


func _release(index: int) -> void:
	if phase == Phase.DONE:
		return
	_trigger_released[index] = true
	for unit: Dictionary in _triggers[index]["units"]:
		for i: int in int(unit["count"]):
			# Reserves come in from outside the outer ring: they are ARRIVING,
			# not materialising on top of you.
			_spawn_unit(unit["type"], &"outer")
	_check_field_cleared()


## ---------- outcomes ----------

func _on_points_scored(points: float, type_id: StringName) -> void:
	# Only while this sortie is actually running. `_on_unit_gone` has always been
	# guarded by `units.has(unit)`; this one was not, so anything still connected
	# from a previous sortie - or killed after the pilot died and the result was
	# already priced into the war - silently topped up a dent nobody would ever
	# read again.
	if phase != Phase.ENGAGED and phase != Phase.EGRESS:
		return
	# BODIES, not units: a gnat is worth its points and its dent even though
	# nine of them are one unit.
	kills[type_id] = int(kills.get(type_id, 0)) + 1
	enemy_destroyed.emit(points)
	_announce_yourself()


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


## THE THIRD TRIGGER (Iteration 13, the archetype opening). `detected` is what
## SEAD, Strike-CAP and the HQ Raid hold their reserves on, and until now nothing
## in the project fired it — so those three archetypes would have held a slice of
## their garrison forever. That is worse than an archetype that does not build:
## reserves are taken OUT of the placed garrison (P2.3), so the sortie would have
## been quietly EASIER than the node it was composed from, and the exchange rate
## that makes "clear everything and you have dented the node by its garrison"
## true would have been wrong by exactly the held fraction.
##
## What counts as being detected: the first time you announce yourself, by
## killing something or by touching the objective. Both routes exist because both
## play styles do — a pilot who fights their way in and a pilot who runs straight
## at the structure must each spring the trap.
##
## THE INGRESS HAS LANDED AND THIS DELIBERATELY DID NOT CHANGE (A6, 2026-08-03).
## The obvious next move is to fire `detected` when a garrison unit can actually
## SEE you, which is now possible for the first time and is what P2.3 means by
## staying unseen. It is held back for one reason: the approach is flown over
## flat, empty ground, because the greybox has no terrain past the arena. With
## nothing to mask behind, being seen is not a decision — a sight test would fire
## at a fixed distance on every sortie, so the only effect would be reserves
## arriving ten seconds earlier, deterministically, with no new counterplay
## bought. That is a difficulty change wearing a mechanic's clothes.
##
## It becomes real the day the biome brings terrain (P1.9, and A6's own
## motivation — *"hills that allow a smart player... fly low to avoid SAM sites,
## until he gets close and then do a surprise attack"*). Detection-on-sight and
## cover are one feature; shipping half of it is shipping the half that only
## takes.
func _announce_yourself() -> void:
	_fire_trigger(&"detected")


func _on_objective_damaged() -> void:
	_fire_trigger(&"objective_damaged")
	_announce_yourself()


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
