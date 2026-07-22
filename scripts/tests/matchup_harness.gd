extends SceneTree

## The matchup harness — balance CI, unit layer (GAMEPLAY-DESIGN Iteration 6,
## H2/H3/H9). Spins up the REAL drone + REAL weapon against a REAL enemy in a
## minimal headless arena, lets the scripted reference pilot (H5) fight it out
## far faster than real time, and prints measured combat outcomes: win rate,
## time-to-kill, damage taken (H4). The paper counter-matrix (P4.3) is the
## spec; this is the test — divergence is a bug in the numbers or a lie in the
## design, caught before anyone flies it.
##
## SCOPE (the rig, on shipped content): the measured matrix covers what exists
## today — the Kestrel flying Blaster/Missile/Flak against the slice-four
## bestiary (Raider, Turret, Gnat, Aegis). The frame axis (P3.4, Atlas) is the
## remaining Phase 4 column. This file is data-driven so a new row is one list
## entry — and every assert addresses cells BY NAME so that stays true.
##
## DETERMINISM (P4.8, Phase 3): every rep seeds the enemy's AI RNG with the rep
## index, so rep N is the same fight run after run and across balance edits —
## a changed number means a changed BALANCE, not a reshuffled die. It is not
## bit-exact: the physics solver carries float variance between processes, so a
## rep sitting on a knife edge (one bolt grazing vs. missing) can still flip.
## Read aggregate movement, not single-rep noise.
##
## Run:   <godot> --headless -s scripts/tests/matchup_harness.gd --path .
## WATCH: <godot> -s scripts/tests/matchup_harness.gd --path .
##
## Drop --headless and the duels render from the reference pilot's own FPV
## camera, in real time, with each matchup announced as it starts. The numbers
## say a cell is 0%; watching says WHY it is 0% — which pass geometry the pilot
## flies, where its shots actually go, whether it is fighting or falling. The
## project's founding tenet applies to the instrument as much as to the game:
## some things are only visible to eyes.

const REPS: int = 6
const MAX_SECONDS: float = 10.0
const ARENA_ALTITUDE: float = 14.0
const ENGAGE_DISTANCE: float = 40.0
## Where a bomber's strike route ends — behind the player, so the intercept
## clock (~60 m of transit) fits inside MAX_SECONDS.
const BOMB_TARGET_Z: float = 20.0
## The FCS gun director's setting while measuring (CombatConfig.
## fire_assist_miss_m). This is the human's own play setting: with the director
## at 0 they "can't get a shot out" at all, because on a radio the trigger
## competes with flying — which is the exact problem FCS was designed to solve.
##
## Measuring the chip gun WITHOUT it would therefore not be a purer test, it
## would be a test of a way nobody plays. Confirmed with the user (2026-07-18):
## the chip gun's `++` against raiders ASSUMES the director. That assumption is
## now explicit here rather than hidden.
const DIRECTOR_MISS_M: float = 1.2

# One entry per measured cell. weapon: blaster|missile|flak; enemy scene;
# "frame" is the airframe flying it (default Kestrel); "paper" is the spec band
# this cell is held to; "mode" picks the banding rule:
#   win  — win-rate against the H4 thresholds (the default ruler)
#   pack — exchange rate (kills vs pack, minus hull spent): a swarm makes
#          win-rate meaningless, because the pack also "loses" by spending
#          itself on your hull (P3.2 finding)
#   hand — the rig cannot measure this cell; the band is the HUMAN's, per the
#          H5 division of labor, and the report says so out loud
#   frame — the P3.4 axis. Bands the EXCHANGE DELTA against the named `datum`
#          cell, which flies the same weapon against the same enemy on the
#          KESTREL. See FRAME_BANDS for why a frame is ruled relatively.
#
# The two axes name their rows differently on purpose: weapon-axis cells read
# "Weapon x Enemy", frame-axis cells read "Frame x Enemy". A row's name says
# which variable it is holding still.
const MATCHUPS: Array[Dictionary] = [
	{"name": "Blaster x Raider", "weapon": "blaster", "type": "raider",
			"enemy": "res://scenes/combat/enemy_drone.tscn",
			"paper": "++", "mode": "hand",
			# User, 2026-07-18: "a tough chance to hit, but the weapon itself
			# is very powerful, specially with high fire rate." The scripted
			# pilot cannot fly the human's sweep-fire passes (calibration task
			# #1, parked); the cell keeps its paper band on the human's word.
			"hand_band": "++"},
	{"name": "Missile x Raider", "weapon": "missile", "type": "raider",
			"enemy": "res://scenes/combat/enemy_drone.tscn",
			"paper": "+", "mode": "win"},
	{"name": "Blaster x Turret", "weapon": "blaster", "type": "turret",
			"enemy": "res://scenes/combat/turret.tscn",
			"paper": "0", "mode": "win"},
	{"name": "Blaster x Gnats", "weapon": "blaster", "type": "gnat",
			"enemy": "res://scenes/combat/gnat_swarm.tscn",
			"paper": "+", "mode": "pack"},
	{"name": "Missile x Gnats", "weapon": "missile", "type": "gnat",
			"enemy": "res://scenes/combat/gnat_swarm.tscn",
			"paper": "--", "mode": "pack"},
	{"name": "Blaster x Aegis", "weapon": "blaster", "type": "aegis",
			"enemy": "res://scenes/combat/aegis.tscn",
			"paper": "--", "mode": "win"},
	{"name": "Missile x Aegis", "weapon": "missile", "type": "aegis",
			"enemy": "res://scenes/combat/aegis.tscn",
			"paper": "++", "mode": "win",
			# P4.3's `++` here is a COMBO band (v1.25, user's call): the doc's
			# own prose says "the combo, not the gun alone", and the aegis's
			# real answer is missile-strips-then-gun-finishes. This cell
			# measures the MISSILE ALONE, which is `+` — good, not excellent,
			# because three launches at a 3 s cadence is a long time to hold
			# an intercept. The combo keeps the `++`, as a derived row
			# (Lethality.combo) rather than a contaminated cell.
			"paper_solo": "+"},
	# --- The flak column (P4.10 / P3.1, added v1.28). The row the whole weapon
	# exists for is Flak x Gnats: the chip gun bands `--` there on a 0.02 hit
	# rate, so if this reads anything less than dominant the gnat row has no
	# answer in the slice at all.
	{"name": "Flak x Gnats", "weapon": "flak", "type": "gnat",
			"enemy": "res://scenes/combat/gnat_swarm.tscn",
			"paper": "++", "mode": "pack"},
	{"name": "Flak x Raider", "weapon": "flak", "type": "raider",
			"enemy": "res://scenes/combat/enemy_drone.tscn",
			"paper": "0", "mode": "win"},
	{"name": "Flak x Turret", "weapon": "flak", "type": "turret",
			"enemy": "res://scenes/combat/turret.tscn",
			"paper": "-", "mode": "win"},
	# Paper `--` for the same arithmetic reason the chip gun is: 10 damage under
	# a 40 break threshold never touches the shield. If this cell ever wins, the
	# threshold gate broke — see the structural assert in _report().
	{"name": "Flak x Aegis", "weapon": "flak", "type": "aegis",
			"enemy": "res://scenes/combat/aegis.tscn",
			"paper": "--", "mode": "win"},
	# --- THE FRAME AXIS (Phase 4b, P3.4/P3.7's second dimension). Paper bands are
	# the Atlas column of P3.4: gnat ++, raider 0, turret -, aegis ++.
	#
	# Each row flies the weapon its Kestrel datum already flies, so the ONLY
	# variable between a frame cell and its datum is the airframe. Choosing the
	# row's "best" weapon instead would have measured a loadout and called it a
	# frame — P4.4's cells describe a mix ("tank + spray", "missile racks"), and
	# a loadout is not a column (P4.3's rule about the FCS, one axis over).
	#
	# Blaster x Raider is unavailable as a datum (hand-mode: the rig cannot fly
	# it), so the raider row is measured with the missile instead.
	{"name": "Atlas x Gnats", "frame": Frames.ATLAS, "weapon": "flak",
			"type": "gnat", "enemy": "res://scenes/combat/gnat_swarm.tscn",
			"paper": "++", "mode": "frame", "datum": "Flak x Gnats"},
	{"name": "Atlas x Raider", "frame": Frames.ATLAS, "weapon": "missile",
			"type": "raider", "enemy": "res://scenes/combat/enemy_drone.tscn",
			"paper": "0", "mode": "frame", "datum": "Missile x Raider"},
	{"name": "Atlas x Turret", "frame": Frames.ATLAS, "weapon": "blaster",
			"type": "turret", "enemy": "res://scenes/combat/turret.tscn",
			"paper": "-", "mode": "frame", "datum": "Blaster x Turret"},
	{"name": "Atlas x Aegis", "frame": Frames.ATLAS, "weapon": "missile",
			"type": "aegis", "enemy": "res://scenes/combat/aegis.tscn",
			"paper": "++", "mode": "frame", "datum": "Missile x Aegis"},
]

## H4 banding, fixed stated thresholds (H.q1: a ruler that does not drift).
## Win-mode: band by reference-pilot win rate.
const WIN_BANDS: Array = [[0.85, "++"], [0.70, "+"], [0.50, "0"], [0.25, "-"]]
## Pack-mode: band by EXCHANGE — fraction of the pack shot down minus fraction
## of the player's hull spent. A perfect rake is +1, absorbing the cloud with
## your face is -1. Thresholds stated, like the win ruler.
const PACK_BANDS: Array = [[0.6, "++"], [0.3, "+"], [0.0, "0"], [-0.3, "-"]]
## Frame-mode: band the exchange DELTA against the Kestrel flying the same
## weapon at the same enemy. Stated constants, symmetric, because the origin is
## a design statement rather than a measurement — P3.3/P3.4 define the Kestrel's
## whole column as zeros ("the frame you fly when intel is stale"), so a frame is
## only ever better or worse than the all-rounder HERE.
##
## Two reasons the frame axis is ruled on exchange rather than win rate, and
## neither is convenience:
##  - A frame does not change whether the weapon kills; it changes what the kill
##    COSTS. Win rate is nearly blind to that (both frames win, one bleeds), and
##    the cost is the entire content of P4.4's table.
##  - It rescues the cells the win ruler cannot resolve at all. An unseeded enemy
##    (turret, aegis) fights six identical duels, so its win rate is 0% or 100%
##    and its band can only read `++` or `--` — but hull spent is a continuous
##    number even in a deterministic duel, so the frame delta resolves where the
##    outcome ruler is quantized to two values.
const FRAME_BANDS: Array = [[0.30, "++"], [0.10, "+"], [-0.10, "0"], [-0.30, "-"]]

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
## Per matchup: does its enemy expose `ai_seed`? Unseeded types fight an
## identical duel every rep (see _deterministic).
var _seeded: Array[bool] = []
var _failures: PackedStringArray = []
var _watching: bool = BenchView.watching()
## Watch mode only: the real game HUD, fed by the same ReticleSolver the game
## uses, so what you see over the pilot's shoulder is what you would see over
## your own — fall line, pipper, range ticks, lock cone.
var _hud: Node = null


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_ticks_max = int(MAX_SECONDS * _pps)
	for _i: int in MATCHUPS.size():
		_results.append([])
	print("[matchup] %d matchups x %d reps, %ds cap  (pilot v%d)"
			% [MATCHUPS.size(), REPS, int(MAX_SECONDS),
			ReferencePilot.PILOT_VERSION])
	BenchView.setup("matchup")
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
			# Watch mode only. This call was missing entirely, so the reticle
			# this file's header promises ("the same reticle you would see over
			# your own shoulder") was built, fed by the shared solver — and
			# never drawn. The point of watching is seeing what the aim loop
			# sees; without it you watch a drone with no instruments.
			if _watching:
				_update_hud()
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
	if _watching:
		BenchView.build_scenery(_arena)
		if _hud == null:
			_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
			root.add_child(_hud)

	var pool := ProjectilePool.new()
	_arena.add_child(pool)

	_drone = Frames.build(String(matchup.get("frame", Frames.KESTREL)))
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ARENA_ALTITUDE, 0.0)
	_health = _drone.get_node("Health") as Health
	# Per duel, not once: the Atlas's 190 and the Kestrel's 100 are different
	# denominators, and "fraction of your own hull spent" is the only currency in
	# which the two frames can be compared at all.
	_player_max = _health.max_health
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())
	var weapon: Weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	# ISOLATION (v1.25): the director is armed ONLY for the cell that is
	# actually measuring the gun. It used to be armed unconditionally, which
	# meant a "Missile x ..." cell quietly ran missile+gun — and against the
	# aegis that is not a rounding error but a different fight: the missile
	# strips the shield for zero hull damage, then the blaster kills an
	# exposed 80-hull bomber in four bolts. The cell reported 2.3 s for a
	# weapon that needs 7.7 s alone. A cell must measure what its label says;
	# the combo is a row of its own (Lethality.combo), not a contaminant.
	weapon.combat_config.fire_assist_miss_m = \
			DIRECTOR_MISS_M if matchup["weapon"] == "blaster" else 0.0

	_enemy = (load(matchup["enemy"]) as PackedScene).instantiate()
	# Per-rep determinism (P4.8): flyers self-randomize in _ready, so the seed
	# must be set before the node enters the tree. Rep index = seed, so rep 3
	# of a cell is the same fight every run and across balance edits.
	var seeded: bool = _enemy.get(&"ai_seed") != null
	if seeded:
		_enemy.set(&"ai_seed", _rep)
	# Whether this cell's reps carry real variation at all (see _deterministic).
	while _seeded.size() <= _matchup_i:
		_seeded.append(true)
	_seeded[_matchup_i] = seeded
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
	_pilot.weapon = weapon
	_pilot.missile = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	_pilot.flak = _drone.get_node("FpvCamera/FlakPod") as FlakPod
	_pilot.weapon_id = matchup["weapon"]
	_pilot.target = _enemy as Node3D
	_pilot.cruise_altitude = ARENA_ALTITUDE
	_duel_ticks = 0

	if _watching:
		BenchView.follow(_drone)
		print("[matchup] --- %s, rep %d/%d ---"
				% [matchup["name"], _rep + 1, REPS])


## Feed the HUD exactly what main.gd feeds it, via the shared solver — the
## reticle in the rig is then the same reticle in the game, by construction.
func _update_hud() -> void:
	if _hud == null or _drone == null or not is_instance_valid(_drone):
		return
	var solution: Dictionary = ReticleSolver.solve(
			root.get_viewport().get_camera_3d(),
			_drone.get_node("FpvCamera/Weapon") as Weapon, _drone,
			(_drone.get_node("FpvCamera/Weapon") as Weapon).combat_config,
			_drone.get_node("FpvCamera/MissileSystem") as MissileSystem,
			self, RunMods.current.lock_cone_mult)
	if solution.is_empty():
		_hud.call(&"clear_reticle")
		return
	_hud.call(&"update_reticle", solution["center"], solution["pipper"],
			solution["arc"], solution["ticks"], solution["lock_radius"],
			solution["hold_radius"], solution["lockable"])
	_hud.call(&"set_health", _health.current, _player_max)


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
	if _watching:
		print("[matchup]     %s in %.1fs (kills %d, hull lost %.0f)"
				% [outcome, float(_duel_ticks) / _pps, _kills,
				_player_max - _health.current])
	# Shots SPENT, alongside the outcome. A cell that fails having fired twice
	# failed for a different reason than one that failed having fired thirty
	# times — the first is a delivery/acquisition problem, the second a
	# lethality one, and without this number they look identical in a report.
	var spent: int = 0
	match MATCHUPS[_matchup_i]["weapon"]:
		"missile":
			spent = (_drone.get_node("FpvCamera/MissileSystem") \
					as MissileSystem).launches
		"flak":
			spent = (_drone.get_node("FpvCamera/FlakPod") as FlakPod).shots_fired
		_:
			spent = (_drone.get_node("FpvCamera/Weapon") as Weapon).shots_fired
	_results[_matchup_i].append({
		"outcome": outcome,
		"ttk": float(_duel_ticks) / _pps,
		"damage_taken": _player_max - _health.current,
		# Recorded per rep because the denominator is the FRAME's hull. Averaging
		# raw damage and dividing by whichever drone happened to be built last is
		# how a 190-hull frame would have read as tankier than it is (or less).
		"hull_frac": (_player_max - _health.current) / maxf(_player_max, 1.0),
		"kills": _kills,
		"spent": spent,
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
		print("[matchup] %-18s win %2d/%d (%.0f%%)  ttk %s  dmg-taken %.1f  kills %.1f  spent %.1f"
				% [MATCHUPS[i]["name"], wins, runs.size(), win_rate * 100.0,
				mean_ttk, dmg_sum / float(runs.size()),
				kill_sum / float(runs.size()), _mean(i, "spent")])
		# How a cell FAILS is the diagnosis: timing out (could not finish it),
		# bombed (ran out of clock), or dead (it finished you) are three
		# different balance problems wearing the same 0%.
		var outcomes: PackedStringArray = []
		for key: String in tally:
			outcomes.append("%s %d" % [key, tally[key]])
		print("[matchup] %-18s   outcomes: %s"
				% ["", ", ".join(outcomes)])

	_print_banded_matrix()

	# Rig-sanity asserts — what the RIG genuinely proves: the reference pilot
	# flies the real physics, engages, and its two aim paths both land — homing
	# (Missile x Raider) and gun-line-on-a-static-target (Blaster x Turret).
	# If either collapses, the harness itself is broken, not the balance.
	#
	# Addressed BY NAME, never by index. These were positional (`_win_rate(1)`,
	# `(2)`, `(5)`) — and this file's own header invites new rows as "one list
	# entry", so Phase 4's flak/Atlas rows would have silently repointed every
	# assert at the wrong cell: the shield-gate check could have ended up
	# guarding a row with no shield in it, passing forever while proving
	# nothing. An assert that can be silently misaimed is worse than no assert.
	_assert_min_win("Missile x Raider", 0.75, "pilot not engaging")
	_assert_min_win("Blaster x Turret", 0.75, "gun-line aim failing")
	# STRUCTURAL asserts: neither the chip gun (25) nor the flak burst (10) can
	# reach the aegis's 40 break threshold, so every round splashes off forever.
	# A single win in either cell means the threshold gate itself broke — a
	# model regression, not a balance drift, so it fails the run like one. Both
	# columns are listed because both are hard-countered by the SAME rule, and
	# an assert that only guards one of them would let the other rot.
	for name: String in ["Blaster x Aegis", "Flak x Aegis"]:
		var index: int = _matchup_index(name)
		if index < 0:
			_failures.append("rig broken: no '%s' cell — the shield-gate assert has nothing to guard"
					% name)
		elif _win_rate(index) > 0.0:
			_failures.append("shield gate broken: %s won %.0f%% — under-threshold fire cracked a shield it cannot"
					% [name, _win_rate(index) * 100.0])
	# STRUCTURAL, frame axis: a frame cell is meaningless without the Kestrel
	# datum it is a delta from, and a missing datum must fail loudly rather than
	# print "?" in a column someone reads as a measurement. Same discipline as
	# the by-name asserts above — a relative ruler with no origin is not a ruler.
	for matchup: Dictionary in MATCHUPS:
		if matchup["mode"] != "frame":
			continue
		var datum: int = _matchup_index(String(matchup["datum"]))
		if datum < 0:
			_failures.append("rig broken: %s bands against datum '%s', which is not in the matrix"
					% [matchup["name"], matchup["datum"]])
		elif MATCHUPS[datum]["weapon"] != matchup["weapon"] \
				or MATCHUPS[datum]["type"] != matchup["type"]:
			# The delta is only "what the frame did" if everything else is held
			# still. Comparing an Atlas flak cell against a Kestrel missile cell
			# would report the loadout and label it the airframe.
			_failures.append("rig broken: %s (%s vs %s) bands against '%s' (%s vs %s) — the datum must differ ONLY by frame"
					% [matchup["name"], matchup["weapon"], matchup["type"],
					matchup["datum"], MATCHUPS[datum]["weapon"],
					MATCHUPS[datum]["type"]])

	if _failures.is_empty():
		print("[matchup] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[matchup] FAIL: %s" % f)
		print("[matchup] FAIL")
		quit(1)


## The mini-web in three columns (Phase 3.5 step 4, BALANCE.md):
##
##   PAPER      — what P4.3 promised.
##   PREDICTED  — Layer 1 lethality x Layer 2 delivery, arithmetic only, with
##                no fight simulated (scripts/balance/prediction.gd).
##   VALIDATED  — what these duels actually measured, by the H4 rulers.
##
## The two gaps mean different things and are flagged separately:
##   paper vs predicted     — the SHIPPED NUMBERS disagree with the design
##                            doc. Something has to move: the config or the
##                            promise.
##   predicted vs validated — an UN-MODELED FACTOR. The model says the shots
##                            are lethal and land; the fight disagreed, so
##                            something outside lethality-and-delivery decided
##                            the cell (survival pressure, a deadline, the
##                            economy, or a second weapon the rig left live).
##                            This gap is the instrument's OUTPUT, not its
##                            error — per BALANCE.md, it names what to go
##                            model or knowingly accept.
##
## ADVISORY through slice bring-up (H.q6): the table informs the human, only
## rig-sanity and structural asserts fail the run. Hand-mode cells keep the
## human's band in the validated column and say whose it is.
func _print_banded_matrix() -> void:
	var factors: Dictionary = BalancePrediction.load_factors()
	if not factors.is_empty() \
			and int(factors.get("pilot_version", -1)) != ReferencePilot.PILOT_VERSION:
		# Never quietly mix rulers: factors measured under another pilot
		# describe another instrument.
		print("[matchup] STALE FACTORS: measured under pilot v%d, running v%d — predicted column blank."
				% [int(factors.get("pilot_version", -1)),
				ReferencePilot.PILOT_VERSION])
		factors = {}
	elif not factors.is_empty() \
			and String(factors.get("config_stamp", "")) != _config_stamp():
		# The other ruler. Factors are measured against specific muzzle speeds,
		# lock cones and enemy speeds; retuning any of them invalidates the
		# measurement even though the pilot never changed.
		print("[matchup] STALE FACTORS: config has changed since they were measured — predicted column blank.")
		print("[matchup] Re-run tools/balance_report (or delivery_bench.gd) to re-measure.")
		factors = {}
	elif factors.is_empty():
		print("[matchup] NO DELIVERY FACTORS (%s missing) — predicted column blank."
				% BalancePrediction.FACTORS_PATH)
		print("[matchup] Run tools/balance_report (or delivery_bench.gd) to measure them.")
	print("[matchup] ---- mini-web: paper -> predicted -> validated (pilot v%d) ----"
			% ReferencePilot.PILOT_VERSION)
	# Said once, out loud: the last two columns are summaries under DIFFERENT
	# rulers — predicted bands a modeled ttk, validated bands the H4 outcome
	# ruler (win rate, or exchange for packs). H.q1 forbids drifting the H4
	# ruler to make the columns match, so the honest move is to name the
	# mismatch and compare the NUMBERS underneath, which the model line prints.
	print("[matchup] (predicted = modeled ttk; validated = H4 outcome ruler — compare the numbers, not just the bands)")
	for i: int in MATCHUPS.size():
		var matchup: Dictionary = MATCHUPS[i]
		var paper: String = matchup["paper"]
		var validated: String
		var detail: String
		match matchup["mode"]:
			"hand":
				validated = matchup["hand_band"]
				detail = "hand-calibrated (H5): the rig cannot fly this cell; band is the human's"
			"pack":
				var exchange: float = _exchange(i)
				validated = _band(exchange, PACK_BANDS)
				detail = "exchange %+.2f (kills %.1f/%d, hull spent %.0f%%)" % [
						exchange, _mean(i, "kills"), int(_bodies(i)),
						_mean(i, "hull_frac") * 100.0]
			"frame":
				var datum: int = _matchup_index(String(matchup["datum"]))
				if datum < 0:
					validated = "?"
					detail = "rig broken: no datum cell '%s'" % matchup["datum"]
				else:
					var delta: float = _exchange(i) - _exchange(datum)
					validated = _band(delta, FRAME_BANDS)
					detail = "vs Kestrel %+.2f (%s: exchange %+.2f / %.0f%% hull vs %+.2f / %.0f%%)" % [
							delta, matchup["weapon"], _exchange(i),
							_mean(i, "hull_frac") * 100.0, _exchange(datum),
							_mean(datum, "hull_frac") * 100.0]
			_:
				validated = _band(_win_rate(i), WIN_BANDS)
				detail = "win %.0f%%" % (_win_rate(i) * 100.0)
				# A cell whose enemy carries no RNG (turret, aegis — a static
				# gun and a fixed strike route, deterministic BY DESIGN, not by
				# oversight) plays the same duel all six times. Its win rate can
				# then only ever be 0% or 100%, so the ruler can only return
				# `++` or `--` — this cell CANNOT report `0` or `+` no matter
				# what the balance is. Say so, or the reader mistakes a
				# resolution limit for a measurement.
				if _deterministic(i):
					detail += " (deterministic enemy: %d identical reps, so this cell can only read ++ or --)" % REPS
		var prediction: Dictionary = _predict(matchup, factors)
		var predicted: String = String(prediction.get("band", "?"))
		# Where P4.3's band covers a COMBO, this cell is held to the solo band
		# instead — measuring one weapon against a band earned by two would
		# fail the cell for a promise it was never making.
		var held_to: String = String(matchup.get("paper_solo", paper))
		print("[matchup] %-18s %3s -> %-3s -> %-3s  %s"
				% [matchup["name"], paper, predicted, validated, detail])
		if matchup.has("paper_solo"):
			print("[matchup] %-18s   paper %s is a COMBO band; this cell is solo, held to %s"
					% ["", paper, held_to])
		if not prediction.is_empty():
			print("[matchup] %-18s   model: %s" % ["", prediction["note"]])
			var ttk_line: String = _ttk_line(i, prediction)
			if ttk_line != "":
				print("[matchup] %-18s   %s" % ["", ttk_line])
			# A FRAME cell's three columns are three different things, and only
			# the outer two are commensurable: paper is P3.4's frame band
			# (relative to the Kestrel), validated is the measured delta (also
			# relative), but predicted is an ABSOLUTE ttk — the model has no
			# survival term at all (BalancePrediction assumption 3), so it
			# cannot express durability, which is most of what a frame IS.
			# Comparing them would manufacture a disagreement out of the
			# model's own stated scope — the frame axis's headline caveat,
			# printed on every frame cell, every run.
			if matchup["mode"] == "frame":
				print("[matchup] %-18s   ^ predicted is ABSOLUTE ttk on this frame; paper and validated are DELTAS vs the Kestrel — not comparable"
						% "")
				print("[matchup] %-18s     (no survival term in the model, so a frame's durability can only show in the validated column)"
						% "")
			elif predicted != held_to:
				print("[matchup] %-18s   ^ PAPER vs PREDICTED: shipped numbers disagree with P4.3"
						% "")
			# Only a real OUTCOME disagreement counts as an un-modeled factor.
			# The two columns summarise under different rulers (predicted bands
			# a modeled ttk, validated bands the H4 win/exchange ruler), so
			# their letters differ routinely without the model being wrong —
			# missile x aegis predicts 6.0 s and duels 8.0 s, a match, while
			# the letters read `0` vs `++`. Flagging that taught nothing and
			# buried the cells that genuinely diverge.
			var model_kills: bool = String(prediction["why"]) == "" \
					and float(prediction["ttk"]) <= MAX_SECONDS
			var fight_wins: bool = _win_rate(i) >= 0.5
			# Frame cells are excluded for the same reason: their validated
			# column is a delta, not an outcome, so "the fight says loss" is
			# not a sentence about them.
			var comparable: bool = matchup["mode"] not in ["pack", "frame"]
			if comparable and model_kills != fight_wins:
				print("[matchup] %-18s   ^ PREDICTED vs VALIDATED: model says %s, the fight says %s — an un-modeled factor decided this cell"
						% ["", "kill" if model_kills else "no kill",
						"win" if fight_wins else "loss"])
			if predicted != validated:
				if matchup["mode"] == "pack":
					# Not commensurable, and saying so beats implying it: the
					# predicted band is a TTK for killing the whole cloud,
					# the validated band is an EXCHANGE rate over a duel that
					# hits the 10 s cap long before the cloud is finished.
					# Read these two as one sentence — "slow, and it costs
					# hull" — not as a contradiction.
					print("[matchup] %-18s   ^ different rulers: predicted = ttk to clear the pack, validated = exchange at the %ds cap"
							% ["", int(MAX_SECONDS)])


## Predict one cell from the layered model. Returns {} when the delivery
## factors for it are unavailable — a blank column, never a guessed one.
func _predict(matchup: Dictionary, factors: Dictionary) -> Dictionary:
	if factors.is_empty():
		return {}
	var weapon: String = matchup["weapon"]
	var type_id: String = matchup["type"]
	var aim_table: Dictionary = factors.get("aim", {})
	var evasion_table: Dictionary = factors.get("evasion", {})
	var aim_key: String = BalancePrediction.aim_key(
			String(matchup.get("frame", Frames.KESTREL)), weapon)
	var evasion_key: String = BalancePrediction.evasion_key(weapon, type_id)
	if not aim_table.has(aim_key) or not evasion_table.has(evasion_key):
		return {}
	var enemy: EnemyConfig = load("res://resources/default_enemy_%s.tres"
			% type_id) as EnemyConfig
	var combat: CombatConfig = load("res://resources/default_combat_config.tres") \
			as CombatConfig
	var aim: float = float(aim_table[aim_key])
	var evasion: float = float(evasion_table[evasion_key])
	# 1.0 for every weapon that damages one body per connect, so this reads as
	# nothing at all until an AREA weapon is in the cell.
	var splash: float = BalancePrediction.splash_for(factors, weapon, type_id)
	# The unit is the CLOUD for distributed types (P4.q5): killing it means
	# killing every body, which is where the pack's economy bites — and where an
	# area weapon stops paying it.
	var bodies: float = maxf(enemy.pack_size, 1.0)
	var prediction: Dictionary = BalancePrediction.predict(
			weapon, combat, enemy, aim, evasion, bodies, splash)
	var splash_note: String = " x splash %.2f" % splash if splash != 1.0 else ""
	if String(prediction["why"]) != "":
		prediction["note"] = "aim %.2f x evasion %.2f%s — %s" \
				% [aim, evasion, splash_note, prediction["why"]]
	else:
		prediction["note"] = "aim %.2f x evasion %.2f = %.2f hit rate%s, %.0f shots%s @ %.1fs, ttk %.1fs" % [
				aim, evasion, prediction["hit_rate"], splash_note,
				prediction["shots_fired"],
				" (%d bodies)" % int(bodies) if bodies > 1.0 else "",
				prediction["cadence"], prediction["ttk"]]
	return prediction


## Predicted ttk vs the ttk the duels actually measured — the like-for-like
## number the two band columns cannot give (different rulers). The model's
## clock starts at the FIRST SHOT, so the duel is expected to run longer by
## roughly one acquisition plus one time-of-flight; that offset is the
## prediction's stated assumption 4, not a divergence.
func _ttk_line(matchup_i: int, prediction: Dictionary) -> String:
	if prediction.is_empty() or String(prediction["why"]) != "":
		return ""
	var wins: int = 0
	var ttk_sum: float = 0.0
	for r: Dictionary in _results[matchup_i]:
		if r["outcome"] == "win":
			wins += 1
			ttk_sum += float(r["ttk"])
	if wins == 0:
		return "ttk: predicted %.1fs, measured — (no win to time)" \
				% prediction["ttk"]
	var measured: float = ttk_sum / float(wins)
	return "ttk: predicted %.1fs, measured %.1fs (%+.1fs = acquisition + flight)" \
			% [prediction["ttk"], measured, measured - float(prediction["ttk"])]


## Bodies in this cell's enemy UNIT — the pack for a distributed type, 1 for
## everything else (P4.q5: the cloud is the unit).
func _bodies(matchup_i: int) -> float:
	var enemy: EnemyConfig = load("res://resources/default_enemy_%s.tres"
			% MATCHUPS[matchup_i]["type"]) as EnemyConfig
	return maxf(enemy.pack_size, 1.0)


## Fraction of the enemy unit destroyed, minus fraction of YOUR OWN hull spent.
## The pack ruler generalized: for a single-body enemy the first term is just the
## win rate, so one number prices "did you win" and "what did it cost" together —
## which is exactly what a frame moves and a win rate cannot see.
func _exchange(matchup_i: int) -> float:
	return _mean(matchup_i, "kills") / _bodies(matchup_i) \
			- _mean(matchup_i, "hull_frac")


func _band(value: float, bands: Array) -> String:
	for entry: Array in bands:
		if value >= float(entry[0]):
			return entry[1]
	return "--"


func _mean(matchup_i: int, key: String) -> float:
	var runs: Array = _results[matchup_i]
	if runs.is_empty():
		return 0.0
	var total: float = 0.0
	for r: Dictionary in runs:
		total += float(r[key])
	return total / float(runs.size())


## True when this cell's enemy exposes no `ai_seed`, so the harness's per-rep
## seeding does nothing and all REPS fight the same battle (a static turret, a
## bomber on a fixed route — deterministic BY DESIGN, not by oversight).
##
## Detected structurally rather than by comparing outcomes: reps of an unseeded
## enemy still differ by a tick or two of float noise, which is not variation
## worth sampling, and reading that noise as "varied" would hide exactly the
## cells this note exists to qualify. Recorded at build time in `_seeded`.
func _deterministic(matchup_i: int) -> bool:
	return matchup_i < _seeded.size() and not _seeded[matchup_i]


## The config half of the factors' provenance (see BalancePrediction). Built
## from the matrix's own types, so a new row's config joins the stamp for free.
func _config_stamp() -> String:
	var seen: Dictionary = {}
	var enemies: Array[EnemyConfig] = []
	for matchup: Dictionary in MATCHUPS:
		var type_id: String = matchup["type"]
		if seen.has(type_id):
			continue
		seen[type_id] = true
		enemies.append(load("res://resources/default_enemy_%s.tres" % type_id)
				as EnemyConfig)
	return BalancePrediction.config_stamp(
			load("res://resources/default_combat_config.tres") as CombatConfig,
			enemies, Frames.all_configs())


## Cell lookup by name — the only way asserts should address a row, so
## inserting a matrix row can never silently re-aim one. -1 when absent.
func _matchup_index(name: String) -> int:
	for i: int in MATCHUPS.size():
		if MATCHUPS[i]["name"] == name:
			return i
	return -1


## A named cell must win at least `floor`, or the RIG (not the balance) is
## broken. A missing cell fails loudly rather than passing vacuously.
func _assert_min_win(name: String, floor_rate: float, why: String) -> void:
	var index: int = _matchup_index(name)
	if index < 0:
		_failures.append("rig broken: no '%s' cell — a rig-sanity assert has nothing to guard"
				% name)
		return
	if _win_rate(index) < floor_rate:
		_failures.append("rig broken: %s win %.0f%% (< %.0f%%) — %s"
				% [name, _win_rate(index) * 100.0, floor_rate * 100.0, why])


func _win_rate(matchup_i: int) -> float:
	var runs: Array = _results[matchup_i]
	if runs.is_empty():
		return 0.0
	var wins: int = 0
	for r: Dictionary in runs:
		if r["outcome"] == "win":
			wins += 1
	return float(wins) / float(runs.size())
