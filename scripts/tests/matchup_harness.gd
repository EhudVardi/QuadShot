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
## Where a bomber's strike route ends — behind the player, so the intercept
## clock (~60 m of transit) fits inside MAX_SECONDS.
const BOMB_TARGET_Z: float = 20.0

# One entry per measured cell. weapon: blaster|missile. enemy scene + label.
const MATCHUPS: Array[Dictionary] = [
	{"name": "Blaster x Raider", "weapon": "blaster",
			"enemy": "res://scenes/combat/enemy_drone.tscn"},
	{"name": "Missile x Raider", "weapon": "missile",
			"enemy": "res://scenes/combat/enemy_drone.tscn"},
	{"name": "Blaster x Turret", "weapon": "blaster",
			"enemy": "res://scenes/combat/turret.tscn"},
	{"name": "Blaster x Gnats", "weapon": "blaster",
			"enemy": "res://scenes/combat/gnat_swarm.tscn"},
	{"name": "Missile x Gnats", "weapon": "missile",
			"enemy": "res://scenes/combat/gnat_swarm.tscn"},
	{"name": "Blaster x Aegis", "weapon": "blaster",
			"enemy": "res://scenes/combat/aegis.tscn"},
	{"name": "Missile x Aegis", "weapon": "missile",
			"enemy": "res://scenes/combat/aegis.tscn"},
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
var _kills: int = 0
var _bombed: bool = false

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
				_retarget()
				_pilot.update(1.0 / _pps)
			if _won:
				_record("win")
			elif _bombed:
				# Distinct from a hull loss: the player is alive and lost anyway.
				_record("bombed")
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
	# Placed BEFORE entering the tree: types read their own position in _ready
	# (the swarm spawns its pack around it, the raider takes its wander home
	# from it), so positioning afterwards would build them around the origin.
	# The arena sits at the origin, so local position is the global one.
	(_enemy as Node3D).position = Vector3(0.0, ARENA_ALTITUDE, -ENGAGE_DISTANCE)
	# The bomber's route runs past the player and ends behind them, which makes
	# the duel a real intercept clock rather than a health bar: ~60 m at its
	# route speed, comfortably inside the duel cap, so "did you kill it in
	# time" is a question the harness can actually answer.
	if _enemy.get(&"route_end") != null:
		_enemy.set(&"route_end", Vector3(0.0, ARENA_ALTITUDE, BOMB_TARGET_Z))
	_arena.add_child(_enemy)
	# Win = the ENEMY is defeated, which for a distributed type means the whole
	# pack (P4.q5: the cloud is the unit, so one dead gnat is not a win). Types
	# that can be cleared say so with `cleared`; single-body types win on their
	# own destroyed(points).
	_won = false
	# Kills the PLAYER scored. For single-body types this is the win itself;
	# for a pack it is the honest half of the story, because a swarm can also
	# leave the field by spending every body on the player's hull.
	_kills = 0
	_bombed = false
	(_enemy as Object).connect(&"destroyed",
			func(_points: float) -> void: _kills += 1)
	if (_enemy as Object).has_signal(&"cleared"):
		(_enemy as Object).connect(&"cleared", func() -> void: _won = true)
	else:
		(_enemy as Object).connect(&"destroyed",
				func(_points: float) -> void: _won = true)
	# A bomber that reaches its target is a LOSS with the player still at full
	# hull — the one outcome a health-bar-only harness would score as a win.
	if (_enemy as Object).has_signal(&"detonated"):
		(_enemy as Object).connect(&"detonated", func() -> void: _bombed = true)

	_pilot = ReferencePilot.new()
	_pilot.drone = _drone
	_pilot.weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_pilot.missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_pilot.use_missile = matchup["weapon"] == "missile"
	_pilot.target = _enemy as Node3D
	_pilot.cruise_altitude = ARENA_ALTITUDE
	_duel_ticks = 0


## A distributed enemy has no single position to aim at, so the pilot is fed
## the nearest live body each tick — the same choice a player makes when a
## cloud arrives, and the reason gnats bankrupt single-target answers.
func _retarget() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	if not _enemy.has_method("nearest_body"):
		return
	_pilot.target = _enemy.call("nearest_body", _drone.global_position) as Node3D


func _record(outcome: String) -> void:
	_results[_matchup_i].append({
		"outcome": outcome,
		"ttk": float(_duel_ticks) / _pps,
		"damage_taken": _player_max - _health.current,
		"kills": _kills,
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
		var kill_sum: float = 0.0
		var tally: Dictionary = {}
		for r: Dictionary in runs:
			tally[r["outcome"]] = int(tally.get(r["outcome"], 0)) + 1
			dmg_sum += float(r["damage_taken"])
			kill_sum += float(r["kills"])
			if r["outcome"] == "win":
				wins += 1
				ttk_sum += float(r["ttk"])
		var win_rate: float = float(wins) / float(runs.size())
		var mean_ttk: String = "%.1fs" % (ttk_sum / float(wins)) if wins > 0 else "-"
		print("[matchup] %-18s win %2d/%d (%.0f%%)  ttk %s  dmg-taken %.1f  kills %.1f"
				% [MATCHUPS[i]["name"], wins, runs.size(), win_rate * 100.0,
				mean_ttk, dmg_sum / float(runs.size()),
				kill_sum / float(runs.size())])
		# How a cell FAILS is the diagnosis: timing out (could not finish it),
		# bombed (ran out of clock), or dead (it finished you) are three
		# different balance problems wearing the same 0%.
		var outcomes: PackedStringArray = []
		for key: String in tally:
			outcomes.append("%s %d" % [key, tally[key]])
		print("[matchup] %-18s   outcomes: %s"
				% ["", ", ".join(outcomes)])

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
	# The gnat cells need the same health warning, for the opposite reason:
	# there the win column LOOKS green and is not measuring what it says.
	print("[matchup] NOTE: for pack types 'win' means the pack left the field, which it")
	print("[matchup]       also does by stinging itself out on the player. Read `kills`")
	print("[matchup]       against pack_size: killing 1 of 9 while losing half your hull")
	print("[matchup]       is a beating that the win column scores as a victory. Banding")
	print("[matchup]       these cells needs kills+damage, not win-rate (P3.4 / H4).")

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
