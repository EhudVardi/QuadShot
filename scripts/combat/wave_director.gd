class_name WaveDirector
extends Node

## Encounter director (roadmap M3/M4). A run is a chain of sorties: each
## sortie is a few escalating waves spawned in a ring around the arena;
## clearing the last wave opens the exit gate, and flying through it starts the
## next, harder sortie. Player death ends the run. Kill accounting flows
## through here so main only sees score events.
##
## WAVES ARE COMPOSED, NOT COUNTED. Until now this file held exactly one enemy
## scene, so every wave of every sortie was raiders and five of the six roster
## types had never once appeared in a run — the dev room had a specimen of each
## and the actual game had none of them. A wave is now a BUDGET of units filled
## from a PLAN: named types taken OUT of the budget, raiders filling whatever
## is left.
##
## "Out of, never on top of" is SortieComposer's discipline for reserves (P2.3)
## borrowed deliberately. The war sim is NOT wired in — M4's run is not the M6
## campaign and must not quietly become it — but the two share a vocabulary so
## they cannot drift apart conceptually.
##
## Adding a bestiary type to the run is a ROSTER row plus a PLAN slot. If it
## ever needs more than that, this file has the wrong shape.
##
## THE UNIT IS THE UNIT (P4.q5). `remaining` counts units, not bodies: a gnat
## cloud is one, and it is gone when it emits `cleared`, not when its first
## body dies. Types that can leave the field WITHOUT dying report that too — a
## bomber that reached its target ends its unit exactly as a dead one does, or
## the wave it belonged to could never clear and the gate would never open.

signal wave_changed(sortie: int, wave: int, remaining: int)
signal enemy_destroyed(points: float)
signal sortie_cleared(sortie: int)
## A wave is down. Separate from `sortie_cleared` because it fires between waves
## as well as at the end of one.
##
## IT RE-ARMS NOTHING. R.q3 answered "a cleared wave refills the magazines" and
## was RETRACTED in v1.93 after the user flew it: the free refill made the gates
## slack and moved the unit of scarcity from the sortie to the wave. Nothing in
## `scripts/` listens to this signal today; `ammo_check._check_no_free_rearm`
## emits it precisely to assert that nothing happens. This docstring described the
## retracted behaviour for six versions, which made it an invitation to re-add the
## exact regression the check exists to catch.
signal wave_cleared(sortie: int, wave: int)
signal run_ended(sorties_cleared: int, waves_cleared: int, kills: int)
## Something about the wave itself the pilot needs told. Kills already speak
## for themselves through the score; a bomber that got through does not.
signal announced(text: String)

## Spawn ring around the arena's rough center (encounter-design constants,
## not flight/input physics).
const ARENA_CENTER := Vector3(-18.0, 0.0, -15.0)
const SPAWN_RADIUS_MIN: float = 40.0
const SPAWN_RADIUS_MAX: float = 70.0
const SPAWN_HEIGHT_MIN: float = 6.0
const SPAWN_HEIGHT_MAX: float = 18.0
## Emplacements sit closer in. The turret's 45 m sight range makes one dropped
## on the flyer ring a decoration rather than a threat.
const GROUND_RADIUS_MIN: float = 22.0
const GROUND_RADIUS_MAX: float = 38.0
## A ground unit is seated on whatever is actually under it, probed from here
## down — a rooftop emplacement is a good outcome, a turret buried inside a
## city box is not.
const GROUND_PROBE_HEIGHT: float = 60.0
## The bomb run: a level pass over the arena's centre, flown ABOVE the skyline
## (the greybox tops out at 24 m). Height is the whole readability of the type
## — you can see exactly where it is going and exactly how long you have — and
## it is also why the run does not wedge itself against a tower, which would
## turn an intercept clock into a wave that never clears.
const BOMB_RUN_HEIGHT: float = 26.0

## Resupply gates, placed per SORTIE rather than per wave (Iteration 10 R4), so
## a sortie has a layout you learn and route around instead of a stream of
## pickups drifting past.
##
## PAD-POOR IS THE DIFFICULTY KNOB P2.6 promised and never had: gate count
## falls as the sortie number rises. Sortie 1 is generous; deep in a run you
## get one gate and a decision about when to spend it.
const GATES_BASE: int = 3
const GATES_DECAY_PER_SORTIE: float = 0.6
const GATES_MIN: int = 1
## Ring they sit on: inside the enemy spawn ring, so re-arming is a detour into
## the middle of the fight rather than a trip to the edge of the map.
const GATE_RADIUS_MIN: float = 18.0
const GATE_RADIUS_MAX: float = 34.0
const GATE_HEIGHT_MIN: float = 5.0
const GATE_HEIGHT_MAX: float = 14.0
## Metres between gates. The first version placed them by pure random sample and
## the user flew into the result: "the ammo gates were spawned clipping into
## each other". Rejection sampling is the whole fix, and this is the distance it
## enforces - comfortably more than two gate widths, so two of them can never
## read as one confusing object.
const GATE_MIN_SEPARATION: float = 16.0
## Clear space a gate needs around it. Checked against real scenery with a
## sphere cast, because a gate half-buried in a tower is worse than no gate: it
## looks flyable and is not.
const GATE_CLEARANCE: float = 3.4
## Placement attempts before giving up on a gate. Failing to place is a fine
## outcome - one fewer gate is a sortie that is slightly harder, where a badly
## placed one is a sortie that lies to you.
const GATE_PLACE_TRIES: int = 40

## One unit of each roster type: what to build, and the handful of facts the
## director needs to place it and to know when it is gone. Everything else the
## type knows about itself. `height` overrides the ring's random altitude for
## types that fly a set profile.
##
## `threat` is the escort flag, and the screamer is the only false: it carries
## no weapon at all, so a wave made only of screamers is a wave with no fight
## in it (P4.3 — it is an escort, and pairing it with something that shoots is
## the point of the type).
const ROSTER: Dictionary = {
	&"raider": {
		"scene": "res://scenes/combat/enemy_drone.tscn",
		"ground": false, "threat": true,
	},
	&"falx": {
		"scene": "res://scenes/combat/falx.tscn",
		"ground": false, "threat": true,
	},
	# `gnat`, not `gnats` — the id every other system already keys off
	# (`EnemyConfig.type_id`, `default_enemy_gnat.tres`, `WarManifest.ROSTER`).
	# This file spelled it plural until Iteration 12, and the cost was three
	# copies of the same translation line in three separate checks.
	&"gnat": {
		"scene": "res://scenes/combat/gnat_swarm.tscn",
		"ground": false, "threat": true,
	},
	&"turret": {
		"scene": "res://scenes/combat/turret.tscn",
		"ground": true, "threat": true,
	},
	# Carries no gun, but it is on a clock against you — a wave with a bomber
	# in it is a wave you can lose without ever being shot at.
	&"aegis": {
		"scene": "res://scenes/combat/aegis.tscn",
		"ground": false, "threat": true, "height": BOMB_RUN_HEIGHT,
	},
	&"screamer": {
		"scene": "res://scenes/combat/screamer.tscn",
		"ground": false, "threat": false,
	},
	# A suicider is a threat even though it never fires a shot: it can end you by
	# arriving, which is the same reason the bomber is flagged `threat`.
	&"lance": {
		"scene": "res://scenes/combat/lance.tscn",
		"ground": false, "threat": true,
	},
	# The heavy DEFENDER (A7). Flies, but it holds a station rather than
	# orbiting, so it reads as a fixed emplacement that happens to hover.
	&"phalanx": {
		"scene": "res://scenes/combat/phalanx.tscn",
		"ground": false, "threat": true,
	},
}

## Composition by sortie (rows) and wave (entries): the named units this wave
## spends its budget on, raiders filling the rest. Past the last row the plan
## repeats it, so a long run keeps the hardest mix and only grows.
##
## PROVISIONAL — this is pacing, and pacing is the human's call (handoff §14).
## The ordering argues with the brief's sketch on one point: the falx lands
## before the cloud, because one fast body teaches "bait the pass, kill it in
## the recovery" without also multiplying the body count, and the cloud is a
## better sortie finale than a mid-sortie surprise.
const PLAN: Array = [
	# Sortie 1 — raiders, then the interceptor, then the swarm.
	[{}, {&"falx": 1}, {&"gnat": 1}],
	# Sortie 2 — ground fire you have to go and dig out, then the cloud under
	# escort: first a falx pulling you off it, then the EW asset that takes
	# your gun director away while it arrives.
	[{&"turret": 1, &"lance": 1}, {&"gnat": 1, &"falx": 1},
			{&"gnat": 1, &"screamer": 1}],
	# Sortie 3+ — where a long run actually lives, so every wave carries a
	# cloud: the pressure that never lets a single-target answer settle. Then
	# the intercept clock, and P4.3's first designed pair — a bomber you must
	# kill in time, escorted by the thing that takes your lock away.
	[{&"gnat": 1, &"falx": 1, &"turret": 1},
			{&"gnat": 1, &"aegis": 1, &"lance": 1},
			{&"gnat": 2, &"aegis": 1, &"screamer": 1, &"phalanx": 1, &"lance": 2}],
	# Sortie 4+ — the escalation anchor arrives (A7), and it changes the SHAPE
	# of a wave rather than its size: a body you cannot beat from one orbit
	# slot, so the cloud and the suicider are now pressure you take while you
	# are being made to move. The screamer beside it is P4.3's cruelest pair —
	# the gun director goes quiet exactly when you need to place your shots.
	[{&"gnat": 1, &"phalanx": 1, &"lance": 1},
			{&"gnat": 1, &"phalanx": 1, &"falx": 1, &"turret": 1},
			{&"gnat": 2, &"phalanx": 1, &"screamer": 1, &"aegis": 1, &"lance": 2}],
]

@export var combat_config: CombatConfig

var sortie: int = 0
## Wave number within the current sortie (resets each sortie).
var wave: int = 0
var waves_cleared: int = 0
var kills: int = 0
var running: bool = false
## True between clearing a sortie's last wave and the player taking the gate.
var awaiting_gate: bool = false
## Units still up in the current wave. UNITS, not bodies — a nine-strong gnat
## cloud is 1. This is the wave's clock and the number the HUD shows.
var remaining: int = 0

## The live units of the current wave, read-only outside this file (the
## headless checks read it to kill exactly the wave and nothing else).
var units: Array[Node] = []
## This sortie's resupply gates. Cleared and rebuilt each sortie, and swept at
## the end of the run alongside the units.
var gates: Array[Node] = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func start_run() -> void:
	if running:
		return
	running = true
	sortie = 1
	wave = 0
	waves_cleared = 0
	kills = 0
	awaiting_gate = false
	units.clear()
	_lay_gates()
	_next_wave()


func end_run() -> void:
	if not running:
		return
	running = false
	# Dying with the gate open still credits the sortie — its waves were won.
	var sorties_cleared: int = sortie if awaiting_gate else sortie - 1
	awaiting_gate = false
	run_ended.emit(maxi(sorties_cleared, 0), waves_cleared, kills)
	# Quiet despawn: queue_free without take_hit awards no points. Tracked
	# units go first — a cloud's container is not in the `enemies` group and an
	# emplacement is in `turrets`, so a group sweep alone would leave both
	# standing after the run ended.
	for unit: Node in units:
		if is_instance_valid(unit):
			unit.queue_free()
	units.clear()
	for gate: Node in gates:
		if is_instance_valid(gate):
			gate.queue_free()
	gates.clear()
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	remaining = 0


## Called by main after the player flies the exit gate (and, once drafts
## exist, picks an upgrade).
func advance_sortie() -> void:
	if not running or not awaiting_gate:
		return
	awaiting_gate = false
	sortie += 1
	wave = 0
	_lay_gates()
	_next_wave()


## The wave's unit list, in spawn order. Static and side-effect free, so a
## check can assert on a composition without building an arena — which is the
## only way to cover sorties nobody has time to fly to.
static func compose(sortie_n: int, wave_n: int, budget: int) -> Array[StringName]:
	var slots: int = maxi(budget, 1)
	var named: Dictionary = plan_entry(sortie_n, wave_n)
	var composed: Array[StringName] = []
	# Named units come OUT of the budget and never take its last slot: every
	# wave keeps at least one raider. That is what makes the budget honest (it
	# is the whole wave, not a base the plan adds to) and it is what guarantees
	# the escort rule below can always be satisfied.
	var room: int = maxi(slots - 1, 0)
	for type_id: StringName in named:
		if not ROSTER.has(type_id):
			push_warning("[waves] plan names unknown roster type %s" % type_id)
			continue
		for i: int in int(named[type_id]):
			if composed.size() >= room:
				break
			composed.append(type_id)
	while composed.size() < slots:
		composed.append(&"raider")
	# THE ESCORT RULE IS ENFORCED BY THE RAIDER BACKBONE ABOVE, and by nothing
	# else. A screamer carries no weapon at all, so a wave of nothing but escorts
	# would be a wave that cannot threaten the pilot.
	#
	# There used to be a repair line here (`if not has_threat(composed): composed[0]
	# = &"raider"`). It was DELETED rather than kept, because `room = slots - 1`
	# guarantees at least one raider in every wave, so the branch could never once
	# execute - and a guard that cannot fire is indistinguishable from a guard that
	# does not work. Keeping it read as protection nobody had ever seen function.
	#
	# If the backbone above ever stops being unconditional, the rule needs a real
	# guard AND a direct test of it, the way `WarManifest._enforce_escort_rule` has
	# one in `manifest_check`. `composition_check` asserts `has_threat` on the
	# OUTPUT of this function, which is the right place for it: that assertion
	# starts failing the moment the backbone goes.
	return composed


## The plan's named units for a sortie/wave, clamped: past the table's last
## row a run keeps flying its hardest mix.
static func plan_entry(sortie_n: int, wave_n: int) -> Dictionary:
	var row: Array = PLAN[clampi(sortie_n - 1, 0, PLAN.size() - 1)]
	return row[clampi(wave_n - 1, 0, row.size() - 1)]


## Does this composition contain anything that puts the player under pressure?
static func has_threat(composed: Array[StringName]) -> bool:
	for type_id: StringName in composed:
		if ROSTER.has(type_id) and bool(ROSTER[type_id]["threat"]):
			return true
	return false


## How many units wave `wave_n` of sortie `sortie_n` is worth. Unchanged from
## the count it has always been — what changed is that it now buys units of
## whatever type the plan names, rather than raiders by construction.
func wave_budget(sortie_n: int, wave_n: int) -> int:
	return maxi(int(combat_config.wave_base_enemies
			+ combat_config.wave_growth * float(wave_n - 1)
			+ combat_config.sortie_enemy_bonus * float(sortie_n - 1)), 1)


func _next_wave() -> void:
	if not running or awaiting_gate:
		return
	wave += 1
	units.clear()
	for type_id: StringName in compose(sortie, wave, wave_budget(sortie, wave)):
		_spawn_unit(type_id)
	remaining = units.size()
	Blackbox.log_event(&"wave", "s%d w%d" % [sortie, wave], float(remaining))
	wave_changed.emit(sortie, wave, remaining)


## How many resupply gates this sortie gets. Falls with the sortie number, so
## the run gets meaner in a way that is about ROUTE rather than about numbers
## of enemies — which is the axis P2.6 wanted and the wave budget cannot give.
func gate_count(sortie_n: int) -> int:
	return maxi(int(round(float(GATES_BASE)
			- GATES_DECAY_PER_SORTIE * float(sortie_n - 1))), GATES_MIN)


## Fresh gates for a sortie. The old ones go with them: a spent gate is a
## landmark for the sortie it belonged to, not litter in the next one.
func _lay_gates() -> void:
	for gate: Node in gates:
		if is_instance_valid(gate):
			gate.queue_free()
	gates.clear()
	var kinds: Array[StringName] = []
	# Alternate, starting with flak: the pod burns its magazine several times
	# faster than the rack does, so an odd gate count should favour it.
	for i: int in gate_count(sortie):
		kinds.append(&"flak" if i % 2 == 0 else &"missile")
	var placed: Array[Vector3] = []
	for kind: StringName in kinds:
		var at: Vector3 = _gate_point(placed)
		if at == Vector3.INF:
			push_warning("[waves] no clear spot for a %s gate this sortie" % kind)
			continue
		placed.append(at)
		var gate := ResupplyGate.new()
		gate.kind = kind
		gate.position = at
		get_parent().add_child(gate)
		# Faced at the middle of the arena, so the approach is a line you fly
		# rather than an angle you have to discover. Done after add_child
		# because look_at needs the node in a tree.
		var flat := Vector3(ARENA_CENTER.x - at.x, 0.0, ARENA_CENTER.z - at.z)
		if flat.length() > 0.1:
			gate.look_at(gate.global_position + flat, Vector3.UP)
		gates.append(gate)
		Blackbox.log_event(&"gate", String(kind), float(gate.charges), at)


## A spot for a gate that is clear of the other gates AND of the scenery, or
## Vector3.INF if the arena is too crowded to find one.
func _gate_point(placed: Array[Vector3]) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_tree().root.world_3d.direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = GATE_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	for attempt: int in GATE_PLACE_TRIES:
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = _rng.randf_range(GATE_RADIUS_MIN, GATE_RADIUS_MAX)
		var at: Vector3 = ARENA_CENTER + Vector3(
				cos(angle) * radius,
				_rng.randf_range(GATE_HEIGHT_MIN, GATE_HEIGHT_MAX),
				sin(angle) * radius)
		var clear: bool = true
		for other: Vector3 in placed:
			if at.distance_to(other) < GATE_MIN_SEPARATION:
				clear = false
				break
		if not clear:
			continue
		if space != null:
			query.transform = Transform3D(Basis.IDENTITY, at)
			# Static scenery only: a raider drifting past is not a reason to
			# reject a spot that will be empty a second later.
			var hits: Array[Dictionary] = space.intersect_shape(query, 4)
			for hit: Dictionary in hits:
				if hit["collider"] is StaticBody3D:
					clear = false
					break
		if clear:
			return at
	return Vector3.INF


func _spawn_unit(type_id: StringName) -> void:
	var row: Dictionary = ROSTER[type_id]
	var unit: Node = (load(row["scene"]) as PackedScene).instantiate()
	var point: Vector3 = _ground_point() if bool(row["ground"]) \
			else _air_point(row.get("height", -1.0))
	# Placed BEFORE entering the tree. Every type reads its own position in
	# _ready — the raider takes its wander home from it, the swarm builds its
	# pack around it, the falx centres its patrol on it — so positioning after
	# add_child builds them all around the origin instead. (This file did
	# exactly that until now, which is why every wave raider in the game's
	# history wandered home to 0,0,0.) Local == global: our parent is the
	# scene root, which sits at the origin.
	(unit as Node3D).position = point
	# The bomber is a CLOCK, not a health bar. Without a route it flies its own
	# heading into empty sky and the wave becomes a fetch quest; with one it
	# runs level from the ring to the middle of the arena, and the wave becomes
	# "kill it in time".
	if unit.get(&"route_end") != null:
		unit.set(&"route_end", ARENA_CENTER + Vector3.UP * BOMB_RUN_HEIGHT)
	# A body that comes back makes its wave permanently unclearable. The
	# arena's own turrets keep their cycle; a wave's emplacement is spent.
	if unit.get(&"respawns") != null:
		unit.set(&"respawns", false)
	get_parent().add_child(unit)
	units.append(unit)
	unit.connect(&"destroyed", _on_points_scored)
	# A STRIPPED MOUNT SCORES BUT IS NOT A KILL (A7). It has to reach the score,
	# or "stripping guns is progress" is a claim the player never sees — the
	# signal existed and NOTHING was connected to it, so six mounts were worth
	# nothing at all while `phalanx_check` happily asserted the signal fired.
	# An assertion about a signal is not an assertion about an outcome.
	#
	# Deliberately NOT routed through `_on_points_scored`, which counts a KILL:
	# a six-mount body would book six kills for one unit, inflating the arcade
	# counter and — far worse in a sortie — the war dent, which is priced per
	# kill per type. You damaged it; you did not destroy anything.
	if (unit as Object).has_signal(&"mount_destroyed"):
		unit.connect(&"mount_destroyed",
				func(points: float) -> void: enemy_destroyed.emit(points))
	# Bound to the unit because `destroyed` carries points and not a place, and
	# salvage has to land where the body was.
	unit.connect(&"destroyed", func(_points: float) -> void:
			if is_instance_valid(unit):
				Salvage.maybe_drop(get_parent(), (unit as Node3D).global_position,
						SALVAGE_CHANCE))
	# The unit is over when the UNIT is over. A cloud says so with `cleared`;
	# for a single body its own death is the same event.
	if (unit as Object).has_signal(&"cleared"):
		unit.connect(&"cleared", _on_unit_gone.bind(unit))
	else:
		unit.connect(&"destroyed",
				func(_points: float) -> void: _on_unit_gone(unit))
	# Left the field without dying: the bomber got through. Opposite outcome,
	# same bookkeeping — the wave has one fewer unit either way.
	if (unit as Object).has_signal(&"detonated"):
		unit.connect(&"detonated", func() -> void:
			announced.emit("bomber reached its target")
			_on_unit_gone(unit))
	Blackbox.log_event(&"spawn", String(type_id), 0.0, point)


## Somewhere on the flyer ring. A negative `height` means "anywhere in the
## band"; a type that flies a set profile names its own.
func _air_point(height: float) -> Vector3:
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = _rng.randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	return ARENA_CENTER + Vector3(
			cos(angle) * radius,
			height if height >= 0.0 \
					else _rng.randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX),
			sin(angle) * radius)


func _ground_point() -> Vector3:
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = _rng.randf_range(GROUND_RADIUS_MIN, GROUND_RADIUS_MAX)
	var at: Vector3 = ARENA_CENTER + Vector3(
			cos(angle) * radius, 0.0, sin(angle) * radius)
	var space: PhysicsDirectSpaceState3D = get_tree().root.world_3d.direct_space_state
	if space == null:
		return at
	var query := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * GROUND_PROBE_HEIGHT, at + Vector3.DOWN * 5.0)
	var hit: Dictionary = space.intersect_ray(query)
	# Only solid scenery seats an emplacement. A hit on a flyer that happens to
	# be overhead is traffic, not ground.
	if not hit.is_empty() and hit["collider"] is StaticBody3D:
		return hit["position"]
	return at


## Chance a dead body leaves salvage, and what it leaves. A cloud drops from
## its individual gnats, which is deliberate: nine cheap bodies at a low rate
## is a steady trickle, and one raider at a high rate is a decision.
const SALVAGE_CHANCE: float = 0.35


## A body died and paid out. Bodies, not units: a gnat is worth its points and
## its place in the combo even though nine of them are one unit.
func _on_points_scored(points: float) -> void:
	kills += 1
	enemy_destroyed.emit(points)


## One unit left the field — killed, cleared, or spent. This is the only thing
## the wave's clock listens to.
func _on_unit_gone(unit: Node) -> void:
	if not units.has(unit):
		return
	units.erase(unit)
	remaining = units.size()
	wave_changed.emit(sortie, wave, remaining)
	if remaining > 0 or not running:
		return
	waves_cleared += 1
	wave_cleared.emit(sortie, wave)
	if wave >= int(combat_config.sortie_waves):
		awaiting_gate = true
		sortie_cleared.emit(sortie)
	else:
		get_tree().create_timer(combat_config.wave_intermission).timeout.connect(_next_wave)
