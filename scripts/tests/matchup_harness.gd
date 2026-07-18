extends SceneTree

## The matchup harness — balance CI, unit layer (GAMEPLAY-DESIGN Iteration 6,
## H2/H3/H9). Spins up the REAL drone + REAL weapon against a REAL enemy in a
## minimal headless arena, lets the scripted reference pilot (H5) fight it out
## far faster than real time, and prints measured combat outcomes: win rate,
## time-to-kill, damage taken (H4). The paper counter-matrix (P4.3) is the
## spec; this is the test — divergence is a bug in the numbers or a lie in the
## design, caught before anyone flies it.
##
## PHASE 1 SCOPE (the rig, on shipped content): the measured matrix only
## covers what exists today — Kestrel flying Blaster/Missile against the
## shipped Raider and Turret. The banded ++..-- matrix and the P4.3 invariants
## arrive as the roster does (Gnat/Aegis/Flak/Atlas, Phases 3-4): this file is
## data-driven so a new row/column is one list entry.
##
## DETERMINISM (P4.8, Phase 3): every rep seeds the enemy's AI RNG with the rep
## index, so rep N is the same fight run after run and across balance edits —
## a changed number means a changed BALANCE, not a reshuffled die. It is not
## bit-exact: the physics solver carries float variance between processes, so a
## rep sitting on a knife edge (one bolt grazing vs. missing) can still flip.
## Read aggregate movement, not single-rep noise.
##
## Run: <godot> --headless -s scripts/tests/matchup_harness.gd --path .

const REPS: int = 6
const MAX_SECONDS: float = 10.0
const ARENA_ALTITUDE: float = 14.0
const ENGAGE_DISTANCE: float = 40.0

# One entry per measured cell. weapon: blaster|missile. enemy scene + label.
const MATCHUPS: Array[Dictionary] = [
	{"name": "Blaster x Raider", "weapon": "blaster",
			"enemy": "res://scenes/combat/enemy_drone.tscn"},
	{"name": "Missile x Raider", "weapon": "missile",
			"enemy": "res://scenes/combat/enemy_drone.tscn"},
	{"name": "Blaster x Turret", "weapon": "blaster",
			"enemy": "res://scenes/combat/turret.tscn"},
]

enum { BUILD, RUN, RECORD }

var _pps: float
var _ticks_max: int
var _phase: int = BUILD
var _matchup_i: int = 0
var _rep: int = 0

# Live duel.
var _arena: Node3D
var _drone: FlightController
var _enemy: Node
var _health: Health
var _pilot: ReferencePilot
var _duel_ticks: int = 0
var _player_max: float = 100.0
var _won: bool = false

# Aggregates, one array of result dicts per matchup index.
var _results: Array[Array] = []
var _failures: PackedStringArray = []


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_ticks_max = int(MAX_SECONDS * _pps)
	for _i: int in MATCHUPS.size():
		_results.append([])
	print("[matchup] %d matchups x %d reps, %ds cap"
			% [MATCHUPS.size(), REPS, int(MAX_SECONDS)])
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	match _phase:
		BUILD:
			_build_duel()
			_phase = RUN
		RUN:
			_duel_ticks += 1
			if _pilot != null:
				_pilot.update(1.0 / _pps)
			if _won:
				_record("win")
			elif _health != null and not _health.alive:
				_record("loss")
			elif _duel_ticks >= _ticks_max:
				_record("timeout")
		RECORD:
			_teardown()
			_advance()


func _build_duel() -> void:
	var matchup: Dictionary = MATCHUPS[_matchup_i]
	_arena = Node3D.new()
	root.add_child(_arena)

	var pool := ProjectilePool.new()
	_arena.add_child(pool)

	_drone = (load("res://scenes/drone/drone.tscn") as PackedScene).instantiate() \
			as FlightController
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ARENA_ALTITUDE, 0.0)
	_health = _drone.get_node("Health") as Health
	_player_max = _health.max_health
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())

	_enemy = (load(matchup["enemy"]) as PackedScene).instantiate()
	# Per-rep determinism (P4.8): flyers self-randomize in _ready, so the seed
	# must be set before the node enters the tree. Rep index = seed, so rep 3
	# of a cell is the same fight every run and across balance edits.
	if _enemy.get(&"ai_seed") != null:
		_enemy.set(&"ai_seed", _rep)
	_arena.add_child(_enemy)
	(_enemy as Node3D).global_position = \
			Vector3(0.0, ARENA_ALTITUDE, -ENGAGE_DISTANCE)
	# Both shipped hostiles expose destroyed(points); that is our win signal.
	_won = false
	(_enemy as Object).connect(&"destroyed",
			func(_points: float) -> void: _won = true)

	_pilot = ReferencePilot.new()
	_pilot.drone = _drone
	_pilot.weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_pilot.missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_pilot.use_missile = matchup["weapon"] == "missile"
	_pilot.target = _enemy as Node3D
	_pilot.cruise_altitude = ARENA_ALTITUDE
	_duel_ticks = 0


func _record(outcome: String) -> void:
	_results[_matchup_i].append({
		"outcome": outcome,
		"ttk": float(_duel_ticks) / _pps,
		"damage_taken": _player_max - _health.current,
	})
	_phase = RECORD


func _teardown() -> void:
	_pilot = null
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null
	_enemy = null
	_health = null


func _advance() -> void:
	_rep += 1
	if _rep >= REPS:
		_rep = 0
		_matchup_i += 1
	if _matchup_i >= MATCHUPS.size():
		_report()
	else:
		_phase = BUILD


func _report() -> void:
	for i: int in MATCHUPS.size():
		var runs: Array = _results[i]
		var wins: int = 0
		var ttk_sum: float = 0.0
		var dmg_sum: float = 0.0
		for r: Dictionary in runs:
			dmg_sum += float(r["damage_taken"])
			if r["outcome"] == "win":
				wins += 1
				ttk_sum += float(r["ttk"])
		var win_rate: float = float(wins) / float(runs.size())
		var mean_ttk: String = "%.1fs" % (ttk_sum / float(wins)) if wins > 0 else "-"
		print("[matchup] %-18s win %2d/%d (%.0f%%)  ttk %s  dmg-taken %.1f"
				% [MATCHUPS[i]["name"], wins, runs.size(), win_rate * 100.0,
				mean_ttk, dmg_sum / float(runs.size())])

	# Phase-1 sanity asserts what the RIG genuinely proves: the reference
	# pilot flies the real physics, engages, and its two aim paths both land —
	# homing (Missile x Raider) and gun-line-on-a-static-target (Blaster x
	# Turret). If either collapses, the harness itself is broken, not the
	# balance.
	if _win_rate(1) < 0.75:
		_failures.append("rig broken: Missile x Raider win %.0f%% (< 75%%) — pilot not engaging"
				% (_win_rate(1) * 100.0))
	if _win_rate(2) < 0.75:
		_failures.append("rig broken: Blaster x Turret win %.0f%% (< 75%%) — gun-line aim failing"
				% (_win_rate(2) * 100.0))

	# Blaster x Raider is REPORTED, not asserted. v0 aims the gun line well
	# but cannot yet gun-run a fast orbiter (a level target + the 44 deg cam
	# uptilt forces diving passes, not hover-sniping) — so this number is not
	# yet a trustworthy measurement of the chip-gun-vs-raider cell (P4.3 says
	# it should be ++). Closing it is the first reference-pilot calibration
	# task (H.q4): teach v1 tracking gun-runs, with the human on feel.
	print("[matchup] NOTE: Blaster x Raider (%.0f%%) is the v0 pilot's known gap —"
			% (_win_rate(0) * 100.0))
	print("[matchup]       moving-target gun-runs are calibration task #1, not a rig fault.")

	if _failures.is_empty():
		print("[matchup] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[matchup] FAIL: %s" % f)
		print("[matchup] FAIL")
		quit(1)


func _win_rate(matchup_i: int) -> float:
	var runs: Array = _results[matchup_i]
	if runs.is_empty():
		return 0.0
	var wins: int = 0
	for r: Dictionary in runs:
		if r["outcome"] == "win":
			wins += 1
	return float(wins) / float(runs.size())
