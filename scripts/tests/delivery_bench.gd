extends SceneTree

## Layer 2 delivery benches (GAMEPLAY-DESIGN v1.23 Phase 3.5 step 3,
## BALANCE.md): the two factors of "can the shot actually land", each measured
## in the isolation that gives it meaning.
##
## AIM BENCH — agent vs STATIC target. The reference pilot flies the real
## drone against a target that cannot move, cannot shoot and cannot die, so
## hits-per-shot measures the AGENT alone: `aim_quality`, the per-agent
## delivery factor (and the axis the FCS gear ladder purchases). Pilot-
## version-dependent by definition, hence the pin in the header.
##
## EVASION BENCH — fixed PERFECT shooter vs the moving enemy flying its real
## AI. The shooter is the real drone frozen in place, its gun re-laid every
## tick onto the exact ballistic solution (lead + gravity drop) and firing at
## full cadence, so hits-per-shot measures the TARGET alone: `evasion`, the
## per-target delivery factor. A static-target control cell proves the
## bench's own solver first — if the perfect shooter cannot hit a stationary
## raider, the rig is broken and the run fails, before any mover is blamed
## for "evading".
##
## What these numbers are NOT (BALANCE.md): win predictions. They multiply
## with Layer 1 lethality into the predicted product that the duel harness
## VALIDATES; divergence there names an un-modeled factor.
##
## Run: <godot> --headless -s scripts/tests/delivery_bench.gd --path .

const ALTITUDE: float = 14.0
const RANGE_M: float = 40.0
## Gnats hold station (pursuit zeroed) mid-envelope instead of closing to
## sting range — the boil is the dodge being measured, not the closure.
const GNAT_RANGE_M: float = 30.0
## Aegis crossing half-width: +/- this on x at RANGE_M, inside missile lock
## range at the edges (sqrt(30^2 + 40^2) = 50 < 60).
const AEGIS_CROSS_M: float = 30.0
## The aim bench mirrors the matchup harness's director setting — the human's
## own play setting, per the 2026-07-18 decision recorded there.
const DIRECTOR_MISS_M: float = 1.2
## Effectively-infinite hull for bodies that must survive the measurement.
const IMMORTAL_HULL: float = 1.0e9
## Routed targets (the aegis) TELEPORT back to their route start when the
## loop restarts, and a shot in the air at that moment is orphaned — a miss
## the target never earned. The shooter holds fire when the target is within
## this many seconds of its route end, sized to each weapon's engagement time.
const ROUTE_HOLD_BOLT_S: float = 1.0
const ROUTE_HOLD_MISSILE_S: float = 3.0
## Control-cell floor: below this the perfect shooter's own solver is broken.
const CONTROL_MIN_RATE: float = 0.9

const RAIDER_SCENE: String = "res://scenes/combat/enemy_drone.tscn"
const SWARM_SCENE: String = "res://scenes/combat/gnat_swarm.tscn"
const AEGIS_SCENE: String = "res://scenes/combat/aegis.tscn"

## kind: aim (pilot flies) | evasion (frozen perfect shooter).
## target: static | raider | gnats | aegis. seconds: firing window.
const CELLS: Array[Dictionary] = [
	{"name": "aim: blaster", "kind": "aim", "weapon": "blaster",
			"target": "static", "seconds": 20.0},
	{"name": "aim: missile", "kind": "aim", "weapon": "missile",
			"target": "static", "seconds": 45.0},
	{"name": "evasion: blaster x static", "kind": "evasion",
			"weapon": "blaster", "target": "static", "seconds": 20.0,
			"control": true},
	{"name": "evasion: blaster x raider", "kind": "evasion",
			"weapon": "blaster", "target": "raider", "seconds": 20.0},
	{"name": "evasion: blaster x gnats", "kind": "evasion",
			"weapon": "blaster", "target": "gnats", "seconds": 20.0},
	{"name": "evasion: blaster x aegis", "kind": "evasion",
			"weapon": "blaster", "target": "aegis", "seconds": 20.0},
	{"name": "evasion: missile x static", "kind": "evasion",
			"weapon": "missile", "target": "static", "seconds": 45.0,
			"control": true},
	{"name": "evasion: missile x raider", "kind": "evasion",
			"weapon": "missile", "target": "raider", "seconds": 45.0},
	{"name": "evasion: missile x aegis", "kind": "evasion",
			"weapon": "missile", "target": "aegis", "seconds": 45.0},
]

enum { BUILD, FIRE, GRACE, RECORD }

var _pps: float
var _combat: CombatConfig
var _phase: int = BUILD
var _cell_i: int = 0
var _results: Array[Dictionary] = []
var _failures: PackedStringArray = []

# Live cell.
var _arena: Node3D
var _drone: FlightController
var _weapon: Weapon
var _missile: MissileSystem
var _pilot: ReferencePilot
var _target: Node
var _enemy_config: EnemyConfig
var _connects: int = 0
var _ticks: int = 0
var _fire_ticks: int = 0
var _grace_ticks: int = 0
var _swarm_spawns: int = 0


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_combat = load("res://resources/default_combat_config.tres") as CombatConfig
	print("[delivery] %d cells  (pilot v%d — aim cells depend on it, evasion cells do not)"
			% [CELLS.size(), ReferencePilot.PILOT_VERSION])
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	match _phase:
		BUILD:
			_build_cell()
			_phase = FIRE
		FIRE:
			_drive()
			_ticks += 1
			if _ticks >= _fire_ticks:
				_cease_fire()
				_phase = GRACE
		GRACE:
			# Shots already in the air still resolve; the pilot keeps flying
			# (a crashed rig would eat its own in-flight bolts' geometry), the
			# perfect shooter keeps tracking, but nobody pulls a trigger.
			_drive()
			_ticks += 1
			if _ticks >= _fire_ticks + _grace_ticks:
				_score_cell()
				_phase = RECORD
		RECORD:
			_teardown()
			_advance()


func _build_cell() -> void:
	var cell: Dictionary = CELLS[_cell_i]
	_arena = Node3D.new()
	root.add_child(_arena)
	var pool := ProjectilePool.new()
	_arena.add_child(pool)

	_drone = (load("res://scenes/drone/drone.tscn") as PackedScene).instantiate() \
			as FlightController
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALTITUDE, 0.0)
	_drone.arm()
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem

	var is_missile: bool = cell["weapon"] == "missile"
	if cell["kind"] == "aim":
		_drone.prime_motors(_drone.hover_throttle())
		_weapon.combat_config.fire_assist_miss_m = \
				DIRECTOR_MISS_M if not is_missile else 0.0
		_pilot = ReferencePilot.new()
		_pilot.drone = _drone
		_pilot.weapon = _weapon
		_pilot.missile = _missile
		_pilot.use_missile = is_missile
		_pilot.cruise_altitude = ALTITUDE
		if is_missile:
			_missile.fire_override = true
	else:
		# The fixed shooter: frozen in space, immortal (a raider shoots back
		# and gnats would otherwise win the bench by attrition), trigger held
		# down — the bench itself lays the gun each tick in _drive().
		_drone.freeze = true
		var drone_health: Health = _drone.get_node("Health") as Health
		drone_health.max_health = IMMORTAL_HULL
		drone_health.revive()
		_weapon.combat_config.fire_assist_miss_m = 0.0
		if is_missile:
			_missile.fire_override = true
		else:
			_weapon.fire_override = true

	_target = _build_target(cell["target"])
	if _pilot != null:
		_pilot.target = _target as Node3D
	_fire_ticks = int(float(cell["seconds"]) * _pps)
	# Let what is already flying land before scoring, so the last launch of
	# the window is not booked as a miss it never had time to disprove.
	var grace_s: float = _combat.missile_lifetime if is_missile \
			else _combat.projectile_lifetime
	_grace_ticks = int(grace_s * _pps)
	_ticks = 0
	_connects = 0


## Build the cell's target. All single-body targets are immortal so one rig
## measures a rate instead of a kill; gnat bodies keep their real hull (one
## connect is one kill there, and the pack respawns when cleared — counting
## dead gnats IS counting connects, no surgery needed).
func _build_target(type: String) -> Node:
	match type:
		"static":
			_enemy_config = _immobilized_raider_config()
			return _spawn_raider(Vector3(0.0, ALTITUDE, -RANGE_M))
		"raider":
			_enemy_config = (load("res://resources/default_enemy_raider.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			return _spawn_raider(Vector3(0.0, ALTITUDE, -RANGE_M))
		"gnats":
			_enemy_config = (load("res://resources/default_enemy_gnat.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.swarm_pursuit_gain = 0.0
			_swarm_spawns = 0
			return _spawn_swarm()
		"aegis":
			_enemy_config = (load("res://resources/default_enemy_aegis.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			var aegis: Node3D = (load(AEGIS_SCENE) as PackedScene).instantiate() \
					as Node3D
			aegis.set(&"enemy_config", _enemy_config)
			aegis.set(&"loop_route", true)
			aegis.position = Vector3(-AEGIS_CROSS_M, ALTITUDE, -RANGE_M)
			aegis.set(&"route_end",
					Vector3(AEGIS_CROSS_M, ALTITUDE, -RANGE_M))
			_arena.add_child(aegis)
			_count_health_connects(aegis.get_node("Health") as Health)
			return aegis
	push_error("unknown target type " + type)
	return null


## A raider that cannot move, see, or die: the static control body, with the
## real raider's hitbox — the whole reason it is this scene and not a box.
func _immobilized_raider_config() -> EnemyConfig:
	var config: EnemyConfig = (load("res://resources/default_enemy_raider.tres")
			as EnemyConfig).duplicate() as EnemyConfig
	config.hull = IMMORTAL_HULL
	config.speed = 0.0
	config.accel = 0.0
	config.sight_range = 0.0
	return config


func _spawn_raider(at: Vector3) -> Node:
	var raider: Node3D = (load(RAIDER_SCENE) as PackedScene).instantiate() as Node3D
	raider.set(&"enemy_config", _enemy_config)
	raider.set(&"ai_seed", 0)
	raider.position = at
	_arena.add_child(raider)
	_count_health_connects(raider.get_node("Health") as Health)
	return raider


func _spawn_swarm() -> Node:
	var swarm: Node3D = (load(SWARM_SCENE) as PackedScene).instantiate() as Node3D
	swarm.set(&"enemy_config", _enemy_config)
	swarm.set(&"ai_seed", _swarm_spawns)
	_swarm_spawns += 1
	swarm.position = Vector3(0.0, ALTITUDE, -GNAT_RANGE_M)
	_arena.add_child(swarm)
	# One scored body = one connect (25 dmg vs 6 hull: every hit kills).
	swarm.connect(&"destroyed", func(_points: float) -> void: _connects += 1)
	# Cleared mid-window: hand the shooter a fresh pack to keep measuring.
	swarm.connect(&"cleared", func() -> void:
			if _phase == FIRE:
				_target = _spawn_swarm())
	return swarm


func _count_health_connects(health: Health) -> void:
	# A connect is a shot that ARRIVED, whatever happened next — absorbed,
	# shield-breaking, or wounding. Evasion is about arriving; lethality
	# (Layer 1) owns the rest. `struck` is the one signal that fires exactly
	# once per arrival.
	health.struck.connect(func(_amount: float) -> void: _connects += 1)


func _drive() -> void:
	if CELLS[_cell_i]["kind"] == "aim":
		if _pilot != null:
			_pilot.update(1.0 / _pps)
		return
	# Perfect shooter: re-lay the gun (and the lock cone) onto the solution.
	var aim_at: Node3D = _live_target_body()
	if aim_at == null:
		return
	var gun_point: Vector3 = _ballistic_aim_point(aim_at)
	if _weapon.global_position.distance_squared_to(gun_point) > 0.01:
		_weapon.look_at(gun_point)
	# The missile homes; the lock cone wants the TRUE bearing, not a lead.
	if _missile.global_position.distance_squared_to(
			aim_at.global_position) > 0.01:
		_missile.look_at(aim_at.global_position)
	_hold_fire_near_route_end(aim_at)


## See ROUTE_HOLD_*: don't book teleport-orphaned shots as evasion.
func _hold_fire_near_route_end(aim_at: Node3D) -> void:
	if _phase != FIRE:
		return
	var route: Variant = _target.get(&"route_end")
	if route is not Vector3:
		return
	var eta: float = ((route as Vector3) - aim_at.global_position).length() \
			/ maxf(_enemy_config.speed, 0.1)
	if CELLS[_cell_i]["weapon"] == "missile":
		_missile.fire_override = eta > ROUTE_HOLD_MISSILE_S
	else:
		_weapon.fire_override = eta > ROUTE_HOLD_BOLT_S


func _live_target_body() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	if _target.has_method("nearest_body"):
		return _target.call("nearest_body", _drone.global_position) as Node3D
	return _target as Node3D


## The exact firing solution: iterate flight time against the target's linear
## prediction, then raise the aim by the bolt's own gravity drop. This is the
## bench's definition of "perfect aim" — anything the target does beyond
## flying straight is, by construction, evasion.
func _ballistic_aim_point(body: Node3D) -> Vector3:
	var origin: Vector3 = _weapon.global_position
	var target_velocity: Vector3 = Vector3.ZERO
	var raw: Variant = body.get(&"velocity")
	if raw is Vector3:
		target_velocity = raw as Vector3
	var predicted: Vector3 = body.global_position
	var flight_time: float = 0.0
	for _i: int in 4:
		flight_time = (predicted - origin).length() \
				/ maxf(_combat.muzzle_speed, 1.0)
		predicted = body.global_position + target_velocity * flight_time
	var drop: float = float(ProjectSettings.get_setting(
			"physics/3d/default_gravity")) * _combat.projectile_gravity_scale
	return predicted + Vector3.UP * (0.5 * drop * flight_time * flight_time)


func _cease_fire() -> void:
	_weapon.fire_override = false
	_missile.fire_override = false
	_weapon.combat_config.fire_assist_miss_m = 0.0


func _score_cell() -> void:
	var cell: Dictionary = CELLS[_cell_i]
	var shots: int = _missile.launches if cell["weapon"] == "missile" \
			else _weapon.shots_fired
	var rate: float = float(_connects) / float(shots) if shots > 0 else 0.0
	_results.append({"shots": shots, "connects": _connects, "rate": rate})
	print("[delivery] %-28s %4d shots, %4d connects  -> %.2f"
			% [cell["name"], shots, _connects, rate])
	if shots == 0:
		_failures.append("%s: fired nothing — rig broken" % cell["name"])
	elif cell.get("control", false) and rate < CONTROL_MIN_RATE:
		_failures.append("%s: control rate %.2f under %.2f — the perfect shooter cannot shoot; fix the bench before reading evasion"
				% [cell["name"], rate, CONTROL_MIN_RATE])


func _teardown() -> void:
	_pilot = null
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null
	_weapon = null
	_missile = null
	_target = null
	_enemy_config = null


func _advance() -> void:
	_cell_i += 1
	if _cell_i >= CELLS.size():
		_report()
	else:
		_phase = BUILD


func _report() -> void:
	print("[delivery] ---- Layer 2 factors (pilot v%d) ----"
			% ReferencePilot.PILOT_VERSION)
	for i: int in CELLS.size():
		print("[delivery] %-28s %.2f" % [CELLS[i]["name"], _results[i]["rate"]])
	if _failures.is_empty():
		print("[delivery] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[delivery] FAIL: %s" % f)
		print("[delivery] FAIL")
		quit(1)
