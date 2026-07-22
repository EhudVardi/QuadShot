extends SceneTree

## Layer 2 delivery benches (GAMEPLAY-DESIGN v1.23 Phase 3.5 step 3,
## BALANCE.md): the two factors of "can the shot actually land", each measured
## in the isolation that gives it meaning.
##
## AIM BENCH — agent vs STATIC target. The reference pilot flies the real
## drone against a target that cannot move, cannot shoot and cannot die, so
## hits-per-shot measures the AGENT alone: `aim_quality`, the per-agent
## delivery factor (and the axis the FCS gear ladder purchases). Pilot-
## version-dependent by definition, hence the pin in the header — and, since
## Phase 4b, FRAME-dependent too: the agent is a pilot flying an airframe, so
## these cells are keyed `<frame>:<weapon>`. That is the whole Layer 2 cost of
## the P3.4 frame axis; nothing else in this file grew.
##
## THESE CELLS FLY THE REPO'S NUMBERS. `Frames.build` turns off user:// config
## loading, because until Phase 4b the benches inherited whatever the human had
## tuned into their own override and every committed factor was a measurement of
## one machine. Turning it off moved `aim: kestrel/blaster` from 0.17 to 0.05 —
## the same pilot and the same weapon, flying the aircraft as it is committed
## rather than as it is tuned.
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
## SPLASH — a THIRD delivery factor, and the flak column is why it exists. Aim
## belongs to the agent and evasion to the target, but "how many bodies does one
## arriving burst cover" belongs to neither: it is the weapon's geometry meeting
## the target's dispersion. So the flak cells report two numbers from one
## measurement — `bursts_connected / shots_fired` (arrival, comparable to every
## other weapon's rate) and `bodies_struck / bursts_connected` (splash) — and
## the prediction layer divides the pack bill by the second. For a weapon that
## damages one body per connect, splash is 1.0 and nothing changes.
##
## What these numbers are NOT (BALANCE.md): win predictions. They multiply
## with Layer 1 lethality into the predicted product that the duel harness
## VALIDATES; divergence there names an un-modeled factor.
##
## Run:   <godot> --headless -s scripts/tests/delivery_bench.gd --path .
## WATCH: <godot> -s scripts/tests/delivery_bench.gd --path .   (tools/watch_delivery)
##
## Drop --headless and the cells render from the rig's own FPV camera. Worth
## doing before believing any factor: an aim cell shows you WHY 0.14 (is the
## pilot missing, or is it fighting the aircraft?), and an evasion cell shows
## you what the target is actually doing to break the solution.

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
const TURRET_SCENE: String = "res://scenes/combat/turret.tscn"

## kind: aim (pilot flies) | evasion (frozen perfect shooter).
## target: static | raider | gnats | aegis. seconds: firing window.
## frame: which airframe flies the cell — AIM cells only. Evasion cells leave it
## unset because the shooter is frozen and its gun is laid by this bench, so the
## airframe cannot influence the shot (see BalancePrediction.aim_key).
const CELLS: Array[Dictionary] = [
	{"name": "aim: kestrel/blaster", "kind": "aim", "weapon": "blaster",
			"frame": Frames.KESTREL, "target": "static", "seconds": 20.0},
	{"name": "aim: kestrel/missile", "kind": "aim", "weapon": "missile",
			"frame": Frames.KESTREL, "target": "static", "seconds": 45.0},
	{"name": "evasion: blaster x static", "kind": "evasion",
			"weapon": "blaster", "target": "static", "seconds": 20.0,
			"control": true},
	{"name": "evasion: blaster x raider", "kind": "evasion",
			"weapon": "blaster", "target": "raider", "seconds": 20.0},
	# A turret cannot dodge at all, so this cell is both a real factor and a
	# second control: anything but ~1.0 means the bench, not the turret. That
	# claim went unenforced at first — the comment said "control" while the
	# flag was missing, so a regression dropping this to 0.5 would have passed
	# in silence. A control that does not guard is just a comment.
	{"name": "evasion: blaster x turret", "kind": "evasion",
			"weapon": "blaster", "target": "turret", "seconds": 20.0,
			"control": true},
	{"name": "evasion: blaster x gnats", "kind": "evasion",
			"weapon": "blaster", "target": "gnats", "seconds": 20.0},
	{"name": "evasion: blaster x aegis", "kind": "evasion",
			"weapon": "blaster", "target": "aegis", "seconds": 20.0},
	{"name": "evasion: missile x static", "kind": "evasion",
			"weapon": "missile", "target": "static", "seconds": 45.0,
			"control": true},
	{"name": "evasion: missile x raider", "kind": "evasion",
			"weapon": "missile", "target": "raider", "seconds": 45.0},
	{"name": "evasion: missile x gnats", "kind": "evasion",
			"weapon": "missile", "target": "gnats", "seconds": 45.0},
	{"name": "evasion: missile x aegis", "kind": "evasion",
			"weapon": "missile", "target": "aegis", "seconds": 45.0},
	# 40 s, not the blaster's 20. The pod's cycle is 4x slower AND its trigger is
	# conditional (no director), so a 20 s window yielded only ~36 shots, and the
	# cell measured 1.00 in one run and 0.92 in the next on nothing but
	# cross-process float variance moving three shells across the 6-degree cone
	# edge.
	#
	# The longer window HALVED that spread but did not remove it: three runs at
	# 40 s read 0.99 / 0.99 / 0.94. More time is not more independent samples
	# here — the pilot flies one quasi-periodic trajectory, so a longer window
	# mostly re-measures the same oscillation. Left as measured rather than
	# chased: the residual spread moves no band (this cell divides into
	# single-digit shot counts), and it sits inside the contract the harness
	# header already states — AI-level deterministic, not bit-exact, read
	# aggregate movement rather than single reps. Recorded so the next reader
	# does not mistake a 0.94/0.99 difference between runs for a balance change.
	#
	# The 0.99/0.99/0.94 spread above was measured on the human's tuned Kestrel,
	# before the benches were pinned to repo defaults. On the committed config it
	# reads 1.00 at a duty of 0.28 — fewer shells, all of them fused. Whether the
	# wobble is gone or merely hiding behind a smaller sample is not yet known;
	# re-check it before quoting this cell to a decimal place.
	{"name": "aim: kestrel/flak", "kind": "aim", "weapon": "flak",
			"frame": Frames.KESTREL, "target": "static", "seconds": 40.0},
	{"name": "evasion: flak x static", "kind": "evasion",
			"weapon": "flak", "target": "static", "seconds": 20.0,
			"control": true},
	{"name": "evasion: flak x raider", "kind": "evasion",
			"weapon": "flak", "target": "raider", "seconds": 20.0},
	{"name": "evasion: flak x turret", "kind": "evasion",
			"weapon": "flak", "target": "turret", "seconds": 20.0,
			"control": true},
	# THE CELL THE WHOLE COLUMN EXISTS FOR (P4.3 flak x gnat = `++`). The
	# blaster reads 0.12 here; if flak does not read dramatically better, the
	# gnat row has no answer and the paper band is a promise nothing keeps.
	{"name": "evasion: flak x gnats", "kind": "evasion",
			"weapon": "flak", "target": "gnats", "seconds": 20.0},
	{"name": "evasion: flak x aegis", "kind": "evasion",
			"weapon": "flak", "target": "aegis", "seconds": 20.0},
	# --- The Atlas's aim cells (Phase 4b, P3.4's frame axis). Three cells, not a
	# second matrix: the frame re-keys aim and touches nothing else, so this is
	# the ENTIRE Layer 2 cost of a new frame. Same windows as the Kestrel's, or
	# the two frames would be measured on different rulers — which is the mistake
	# the duty-cycle line exists to warn about, one axis over.
	{"name": "aim: atlas/blaster", "kind": "aim", "weapon": "blaster",
			"frame": Frames.ATLAS, "target": "static", "seconds": 20.0},
	{"name": "aim: atlas/missile", "kind": "aim", "weapon": "missile",
			"frame": Frames.ATLAS, "target": "static", "seconds": 45.0},
	{"name": "aim: atlas/flak", "kind": "aim", "weapon": "flak",
			"frame": Frames.ATLAS, "target": "static", "seconds": 40.0},
]

## Every roster config whose numbers can move a measured delivery factor —
## the stamp's input set. A new bestiary type belongs here the day it lands,
## or its stats can drift without invalidating the factors measured under them.
const ENEMIES_FOR_STAMP: Array[String] = [
	"res://resources/default_enemy_raider.tres",
	"res://resources/default_enemy_turret.tres",
	"res://resources/default_enemy_gnat.tres",
	"res://resources/default_enemy_aegis.tres",
]

## Bench target name -> EnemyConfig.type_id, so the artifact is keyed by the
## roster's own vocabulary rather than by this file's cell names. `static` is
## the bench's own control body, not a roster type, and is written to its own
## section instead of the evasion table.
const TYPE_IDS: Dictionary = {
	"raider": "raider", "turret": "turret", "gnats": "gnat", "aegis": "aegis",
}

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
var _flak: FlakPod
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
	BenchView.setup("delivery")
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
			# _drive() runs the PILOT on aim cells, and the pilot re-arms
			# `missile.fire_override` every tick — so ceasing fire once at the
			# start of GRACE does not hold. Late launches then cannot possibly
			# resolve inside the window and book as pure misses, biasing
			# aim:missile DOWN. Invisible today only because that cell reads
			# 1.00; it would quietly tax any harder aim-missile target.
			_cease_fire()
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
	BenchView.build_scenery(_arena)
	var pool := ProjectilePool.new()
	_arena.add_child(pool)

	# Evasion cells freeze the shooter, so the airframe cannot reach the result;
	# they fly the Kestrel to have something concrete to freeze.
	_drone = Frames.build(String(cell.get("frame", Frames.KESTREL)))
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALTITUDE, 0.0)
	_drone.arm()
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod

	var weapon_id: String = cell["weapon"]
	var is_missile: bool = weapon_id == "missile"
	if cell["kind"] == "aim":
		_drone.prime_motors(_drone.hover_throttle())
		# The gun director belongs to the CHIP GUN cell only. The missile has
		# its own launch logic and the flak pod has none by design, so arming it
		# anywhere else would put a second weapon in the cell (v1.25's lesson).
		_weapon.combat_config.fire_assist_miss_m = \
				DIRECTOR_MISS_M if weapon_id == "blaster" else 0.0
		_pilot = ReferencePilot.new()
		_pilot.drone = _drone
		_pilot.weapon = _weapon
		_pilot.missile = _missile
		_pilot.flak = _flak
		_pilot.weapon_id = weapon_id
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
		match weapon_id:
			"missile":
				_missile.fire_override = true
			"flak":
				_flak.fire_override = true
			_:
				_weapon.fire_override = true

	_target = _build_target(cell["target"])
	if _pilot != null:
		_pilot.target = _target as Node3D
	BenchView.follow(_drone)
	if BenchView.watching():
		print("[delivery] --- %s (%ds window) ---"
				% [cell["name"], int(float(cell["seconds"]))])
	_fire_ticks = int(float(cell["seconds"]) * _pps)
	# Let what is already flying land before scoring, so the last launch of
	# the window is not booked as a miss it never had time to disprove.
	var grace_s: float = _combat.projectile_lifetime
	match weapon_id:
		"missile":
			grace_s = _combat.missile_lifetime
		"flak":
			grace_s = _combat.flak_shell_lifetime
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
		"turret":
			_enemy_config = (load("res://resources/default_enemy_turret.tres")
					as EnemyConfig).duplicate() as EnemyConfig
			_enemy_config.hull = IMMORTAL_HULL
			var turret: Node3D = (load(TURRET_SCENE) as PackedScene).instantiate() \
					as Node3D
			turret.set(&"enemy_config", _enemy_config)
			# Held at the shooter's altitude rather than on a floor the bench
			# does not build: what is measured is that it cannot dodge, and
			# height has no bearing on that.
			turret.position = Vector3(0.0, ALTITUDE, -RANGE_M)
			_arena.add_child(turret)
			_count_health_connects(turret.get_node("Health") as Health)
			return turret
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
	var gun_point: Vector3 = _ballistic_aim_point(aim_at,
			_combat.muzzle_speed, _combat.projectile_gravity_scale)
	if _weapon.global_position.distance_squared_to(gun_point) > 0.01:
		_weapon.look_at(gun_point)
	# The missile homes; the lock cone wants the TRUE bearing, not a lead.
	if _missile.global_position.distance_squared_to(
			aim_at.global_position) > 0.01:
		_missile.look_at(aim_at.global_position)
	# Flak flies its own, slower, droopier arc, so it gets its own solution.
	# Aimed at the BODY, not at a fuse standoff: the shell decides when to burst
	# and that decision is the weapon's, not the shooter's.
	var flak_point: Vector3 = _ballistic_aim_point(aim_at,
			_combat.flak_muzzle_speed, _combat.flak_shell_gravity_scale)
	if _flak.global_position.distance_squared_to(flak_point) > 0.01:
		_flak.look_at(flak_point)
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
	match CELLS[_cell_i]["weapon"]:
		"missile":
			_missile.fire_override = eta > ROUTE_HOLD_MISSILE_S
		"flak":
			_flak.fire_override = eta > ROUTE_HOLD_BOLT_S
		_:
			_weapon.fire_override = eta > ROUTE_HOLD_BOLT_S


func _live_target_body() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	if _target.has_method("nearest_body"):
		return _target.call("nearest_body", _drone.global_position) as Node3D
	return _target as Node3D


## The exact firing solution: iterate flight time against the target's linear
## prediction, then raise the aim by the round's own gravity drop. This is the
## bench's definition of "perfect aim" — anything the target does beyond
## flying straight is, by construction, evasion. Parameterized by muzzle speed
## and gravity scale so each weapon is measured against ITS OWN perfect shot,
## not the blaster's.
func _ballistic_aim_point(body: Node3D, muzzle_speed: float,
		gravity_scale: float) -> Vector3:
	var origin: Vector3 = _weapon.global_position
	var target_velocity: Vector3 = Vector3.ZERO
	var raw: Variant = body.get(&"velocity")
	if raw is Vector3:
		target_velocity = raw as Vector3
	var predicted: Vector3 = body.global_position
	var flight_time: float = 0.0
	for _i: int in 4:
		flight_time = (predicted - origin).length() / maxf(muzzle_speed, 1.0)
		predicted = body.global_position + target_velocity * flight_time
	var drop: float = float(ProjectSettings.get_setting(
			"physics/3d/default_gravity")) * gravity_scale
	return predicted + Vector3.UP * (0.5 * drop * flight_time * flight_time)


func _cease_fire() -> void:
	_weapon.fire_override = false
	_missile.fire_override = false
	_flak.fire_override = false
	_weapon.combat_config.fire_assist_miss_m = 0.0


func _score_cell() -> void:
	var cell: Dictionary = CELLS[_cell_i]
	var weapon_id: String = cell["weapon"]
	var shots: int = 0
	var connects: int = 0
	# Splash: bodies covered per ARRIVING burst. Exactly 1.0 for every weapon
	# that damages one body per connect, which is what makes it a free extension
	# rather than a new dimension (BALANCE.md, assumption 3b).
	var splash: float = 1.0
	match weapon_id:
		"missile":
			shots = _missile.launches
			connects = _connects
		"flak":
			# Counted weapon-side, because an area weapon needs the two numbers
			# separated: `bursts_connected` is arrival (comparable with every
			# other cell's rate) and `bodies_struck` is coverage.
			shots = _flak.shots_fired
			connects = _flak.bursts_connected
			if connects > 0:
				splash = float(_flak.bodies_struck) / float(connects)
			# CROSS-CHECK of two independent counters: the pod counts bodies as
			# it damages them, the TARGET counts arrivals through Health.struck /
			# the swarm's own kill signal. They must agree, and if they ever
			# stop, one of the two is lying about a number the whole flak column
			# is derived from.
			if _connects != _flak.bodies_struck:
				_failures.append("%s: target-side connects %d != pod-side bodies struck %d — the two counters disagree"
						% [cell["name"], _connects, _flak.bodies_struck])
		_:
			shots = _weapon.shots_fired
			connects = _connects
	var rate: float = float(connects) / float(shots) if shots > 0 else 0.0
	var duty: float = _duty_cycle(cell, shots)
	_results.append({"shots": shots, "connects": connects, "rate": rate,
			"splash": splash, "duty": duty})
	var splash_note: String = "  splash %.2f bodies/burst" % splash \
			if weapon_id == "flak" else ""
	print("[delivery] %-28s %4d shots, %4d connects  -> %.2f  (duty %.2f)%s"
			% [cell["name"], shots, connects, rate, duty, splash_note])
	if shots == 0:
		_failures.append("%s: fired nothing — rig broken" % cell["name"])
	elif cell.get("control", false) and rate < CONTROL_MIN_RATE:
		_failures.append("%s: control rate %.2f under %.2f — the perfect shooter cannot shoot; fix the bench before reading evasion"
				% [cell["name"], rate, CONTROL_MIN_RATE])


## Shots taken as a fraction of shots the cadence ALLOWED in the window.
##
## Reported because the flak column made an old conflation visible: `aim` is
## hits-per-shot-FIRED, so it says nothing about how often a shot was taken, and
## the two aim cells do not pull their triggers the same way. The blaster's is
## pulled by the gun director, which fires on any arc solution and so takes many
## marginal shots (duty ~0.4, aim 0.17); the flak pod has no director, so the
## pilot only fires inside a 6-degree cone and nearly every shell fuses (duty
## ~0.7, aim 1.00). Reading 1.00 against 0.17 as "flak aims six times better"
## would be reading two different rulers — the same mistake, in a new column,
## that Blaster x Raider cost a whole phase.
##
## Deliberately NOT folded into the model. Prediction assumes shots arrive at
## the weapon's full cadence (assumption 2), so a duty under 1.0 is a standing
## OPTIMISM in every predicted ttk — pre-existing, not new, and it belongs in
## the report as a named factor rather than in a quiet correction coefficient.
func _duty_cycle(cell: Dictionary, shots: int) -> float:
	var cadence: float = 1.0 / maxf(_combat.fire_rate, 0.001)
	match String(cell["weapon"]):
		"missile":
			cadence = maxf(_combat.missile_cooldown, 0.001)
		"flak":
			cadence = 1.0 / maxf(_combat.flak_fire_rate, 0.001)
	var allowed: float = float(cell["seconds"]) / cadence
	return float(shots) / allowed if allowed > 0.0 else 0.0


func _teardown() -> void:
	_pilot = null
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null
	_weapon = null
	_missile = null
	_flak = null
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
		var splash: float = float(_results[i]["splash"])
		print("[delivery] %-28s %.2f  (duty %.2f)%s" % [CELLS[i]["name"],
				_results[i]["rate"], _results[i]["duty"],
				"   x %.2f bodies/burst" % splash if splash != 1.0 else ""])
	print("[delivery] duty = shots taken / shots the cadence allowed. Aim cells with")
	print("[delivery] different duty measured under different TRIGGER policies, so their")
	print("[delivery] hit rates are not directly comparable (see _duty_cycle).")
	_write_factors()
	if _failures.is_empty():
		print("[delivery] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[delivery] FAIL: %s" % f)
		print("[delivery] FAIL")
		quit(1)


## Leave the measured factors where the prediction layer can find them, as a
## COMMITTED artifact: the delivery table is the pinned pilot's ruler, so it
## belongs in the repo next to PILOT_VERSION, diffable, with the version it
## was measured under written inside it. A factors file whose pilot_version
## does not match the code is stale by construction and says so.
func _write_factors() -> void:
	var aim: Dictionary = {}
	var evasion: Dictionary = {}
	var control: Dictionary = {}
	var splash: Dictionary = {}
	for i: int in CELLS.size():
		var cell: Dictionary = CELLS[i]
		var rate: float = snappedf(float(_results[i]["rate"]), 0.01)
		var yield_per_burst: float = snappedf(float(_results[i]["splash"]), 0.01)
		var weapon: String = cell["weapon"]
		if cell["kind"] == "aim":
			aim[BalancePrediction.aim_key(String(cell["frame"]), weapon)] = rate
		elif cell["target"] == "static":
			control[BalancePrediction.evasion_key(weapon, "static")] = rate
		else:
			var type_id: String = TYPE_IDS[cell["target"]]
			evasion[BalancePrediction.evasion_key(weapon, type_id)] = rate
			# Only written when it is not the identity, so the artifact stays a
			# record of what an AREA weapon does rather than a wall of 1.00s.
			if yield_per_burst != 1.0:
				splash[BalancePrediction.splash_key(weapon, type_id)] = \
						yield_per_burst
	# Stamped with BOTH rulers these factors were measured under: the pilot
	# that flew them and the config numbers they were flown against — weapons,
	# bestiary, and (since Phase 4b) the frames' own flight models, which were
	# always a delivery input and were never stamped. Either drifting makes the
	# file stale, and the reader refuses it rather than quoting measurements
	# taken under different physics.
	var enemies: Array[EnemyConfig] = []
	for path: String in ENEMIES_FOR_STAMP:
		enemies.append(load(path) as EnemyConfig)
	var payload: Dictionary = {
		"pilot_version": ReferencePilot.PILOT_VERSION,
		"config_stamp": BalancePrediction.config_stamp(_combat, enemies,
				Frames.all_configs()),
		"aim": aim,
		"evasion": evasion,
		"splash": splash,
		"control": control,
	}
	DirAccess.make_dir_recursive_absolute(
			BalancePrediction.FACTORS_PATH.get_base_dir())
	var file: FileAccess = FileAccess.open(
			BalancePrediction.FACTORS_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("could not write %s" % BalancePrediction.FACTORS_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.close()
	print("[delivery] wrote %s" % BalancePrediction.FACTORS_PATH)
