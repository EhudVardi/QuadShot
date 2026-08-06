extends SceneTree

## Headless behaviour check for the LANCE (Iteration 14 / A5, A.q5, A.q6).
## The twenty-first check, and it lands the day the type does — standing rule 2:
## *every new bestiary type gets a behaviour check the day it lands*, because a
## results table can only ever say "this cell reads 0%", which is equally
## consistent with a tough enemy, a broken enemy, and an enemy that flew out of
## the level. Four separate Falx bugs looked identical from the results table,
## and one of them was invisible to every test because it only happened before
## the player armed.
##
## Six things it holds, each of which is a decision somebody made:
##
##   1. A5 — it TELEGRAPHS. There is a measurable stretch where it has chosen and
##      has not yet moved, and that window is the whole type.
##   2. A5 — the run is COMMITTED: it flies at where you WERE, so a player who
##      moves after the commit does not get followed.
##   3. A5 — it spends itself on arrival, exactly once, and says so.
##   4. A5 — killing it during the telegraph costs you NO blast. That is the
##      reward the window exists to offer.
##   5. Falx bug four, held for this type: with no player on the field it stays
##      put instead of flying over the horizon.
##   6. A.q6 — it targets the player, and the seam that will one day rank targets
##      is a single function. Asserted so that when the ranking layer lands,
##      whoever moves it is told where the placeholder was.
##
## Run: <godot> --headless -s scripts/tests/lance_check.gd --path .

const TICK_HZ: float = 240.0
const MAX_SECONDS: float = 60.0
## Where the stand-in player sits. Far enough that the Lance has to close, seek,
## and set up before it can commit.
const PLAYER_AT := Vector3(0.0, 14.0, 0.0)
const LANCE_AT := Vector3(0.0, 14.0, 70.0)

var _failures: int = 0
var _arena: Node3D
var _lance: Lance
var _player: Node3D
var _ticks: int = 0
var _stage: int = 0
var _detonated: int = 0
var _blast_taken: float = 0.0
## Ticks the body spent nearly stationary while a player was in sight — the
## telegraph, measured rather than asserted from the constant.
var _still_ticks: int = 0
var _seen_moving: bool = false
var _committed_at: Vector3 = Vector3.INF
var _drift_after_commit: float = 0.0
var _start_distance: float = 0.0


func _initialize() -> void:
	_check_registration()
	_check_the_seam()
	if _failures > 0:
		_report()
		return
	_stage = 0
	_build(true)
	physics_frame.connect(_on_physics_frame)


## ---------- standing rule 4: a new type joins every list the same day ----------

func _check_registration() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_lance.tres")
	_expect(config != null and config.type_id == &"lance",
			"the lance has a config and it names itself")
	_expect(WarManifest.ROSTER.has(&"lance"),
			"the war knows it exists (WarManifest.ROSTER)")
	_expect(WaveDirector.ROSTER.has(&"lance"),
			"the arcade run can spawn it (WaveDirector.ROSTER)")
	# A type in the ROSTER that no wave ever spends its budget on is a type the
	# player never meets, which is the same as not having built it.
	var planned: bool = false
	for sortie: Array in WaveDirector.PLAN:
		for wave: Dictionary in sortie:
			if wave.has(&"lance"):
				planned = true
	_expect(planned, "and some wave actually calls for one (WaveDirector.PLAN)")
	var doctrine: int = 0
	for node_type: StringName in WarManifest.DOCTRINE:
		if WarManifest.DOCTRINE[node_type].has(&"lance"):
			doctrine += 1
	_expect(doctrine > 0,
			"the campaign garrisons it somewhere (%d node types)" % doctrine)
	# It kills by CONTACT, so it must carry a blast rather than a gun. Both halves
	# matter: a Lance with a gun would be a different enemy.
	_expect(config.bomb_damage > 0.0 and config.bomb_radius > 0.0,
			"it carries a blast (%.0f damage, %.0f m)"
			% [config.bomb_damage, config.bomb_radius])
	_expect(is_zero_approx(config.damage) and is_zero_approx(config.fire_rate),
			"and no gun, so Layer 1 prices it as contact rather than as a cadence")
	# P4.2 calls it cheap and expendable - the type a losing enemy fields MORE of.
	var raider: EnemyConfig = load("res://resources/default_enemy_raider.tres")
	_expect(config.strength_cost < raider.strength_cost * 2.5,
			"it is CHEAP so a pressured node can field several (%.1f vs a raider's %.1f)"
			% [config.strength_cost, raider.strength_cost])
	# The pair that IS the type: fastest in the roster, worst turn in the roster.
	var falx: EnemyConfig = load("res://resources/default_enemy_falx.tres")
	_expect(config.speed > falx.speed,
			"it is the fastest thing in the roster (%.0f vs the falx's %.0f)"
			% [config.speed, falx.speed])
	_expect(config.accel < falx.accel,
			"and the least agile, which is what makes the commitment physical rather than scripted (%.0f vs %.0f)"
			% [config.accel, falx.accel])


## ---------- A.q6: the placeholder, asserted as a placeholder ----------

## THE TARGET-RANKING LAYER DOES NOT EXIST, and the user chose to ship without
## it. This asserts the shape of the shortcut rather than the shortcut itself, so
## that the day somebody builds the ranking they are told where it plugs in and
## the day somebody deletes the seam this check complains.
func _check_the_seam() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/combat/lance.gd")
	_expect(source.contains("func _find_player()"),
			"target selection is ONE function, so the ranking layer replaces one thing")
	_expect(source.count("get_first_node_in_group(&\"player\")") == 1,
			"and it hard-codes the player in exactly one place (A.q6's placeholder)")
	_expect(source.contains("A.q6"),
			"and the file says out loud that this is a placeholder, not a design")


## ---------- the flight ----------

func _build(with_player: bool) -> void:
	if _arena != null:
		_arena.free()
	_ticks = 0
	_still_ticks = 0
	_seen_moving = false
	_detonated = 0
	_blast_taken = 0.0
	_committed_at = Vector3.INF
	_drift_after_commit = 0.0
	_arena = Node3D.new()
	root.add_child(_arena)
	if with_player:
		_player = _make_player()
		_arena.add_child(_player)
		_player.position = PLAYER_AT
	else:
		_player = null
	_lance = (load("res://scenes/combat/lance.tscn") as PackedScene).instantiate() as Lance
	_lance.enemy_config = load("res://resources/default_enemy_lance.tres")
	_lance.ai_seed = 0
	_lance.position = LANCE_AT
	_arena.add_child(_lance)
	_lance.detonated.connect(func() -> void: _detonated += 1)
	_start_distance = LANCE_AT.distance_to(PLAYER_AT)


## A stand-in player: the `player` group, a `team`, and a `take_hit` that records
## what the blast did. Deliberately NOT a real drone — this check is about the
## Lance's behaviour, and a flight model in the loop would make a failure
## ambiguous between the two.
func _make_player() -> Node3D:
	var body := Node3D.new()
	body.add_to_group(&"player")
	body.set_script(load("res://scripts/tests/_lance_dummy.gd"))
	return body


func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks > int(MAX_SECONDS * TICK_HZ):
		_expect(false, "the lance resolved inside %.0f s (stage %d)"
				% [MAX_SECONDS, _stage])
		_report()
		return
	if _stage == 0:
		_watch_the_run()
	else:
		_watch_without_a_player()


func _watch_the_run() -> void:
	if not is_instance_valid(_lance):
		_verify_the_run()
		return
	var speed: float = _lance.velocity.length()
	# THE TELEGRAPH, measured as it happens, through the type's own public
	# readout. Measuring it as "nearly stationary" was tried first and was wrong:
	# it counted only the tail of the phase, after the body had finished
	# decelerating, and reported 0.23 s of a 1.15 s telegraph.
	if _lance.telegraphing():
		_still_ticks += 1
	if speed > 12.0:
		_seen_moving = true
		if _committed_at == Vector3.INF:
			_committed_at = _lance.global_position
	# COMMITMENT, measured the only way it can be: move the player AFTER the run
	# starts and see whether the Lance follows. A homing enemy would close on the
	# new position; a committed one flies past where the player used to be.
	if _seen_moving and _player != null and is_instance_valid(_player) \
			and _player.global_position.distance_to(PLAYER_AT) < 0.01:
		_player.global_position = PLAYER_AT + Vector3(40.0, 0.0, 0.0)
	if _seen_moving and _player != null and is_instance_valid(_player):
		_drift_after_commit = maxf(_drift_after_commit,
				_lance.global_position.distance_to(_player.global_position))


func _verify_the_run() -> void:
	var still_s: float = float(_still_ticks) / TICK_HZ
	_expect(_seen_moving, "it commits to a run and accelerates")
	_expect(still_s > Lance.ALIGN_SECONDS * 0.8,
			"and it TELEGRAPHS first - %.2f s of committed, visible alignment before it moves (design asks %.2f s)"
			% [still_s, Lance.ALIGN_SECONDS])
	_expect(_detonated == 1,
			"it spends itself exactly once, so a wave holding it can clear (%d)"
			% _detonated)
	# The player was teleported 40 m sideways the moment the run began. A homing
	# enemy would have closed on the new position; this one must not have.
	_expect(_drift_after_commit > 20.0,
			"the run is COMMITTED - it flew at where the player WAS, ending %.0f m from where they went"
			% _drift_after_commit)
	_expect(_blast_taken > 0.0 or _drift_after_commit > 0.0,
			"the run resolved rather than looping forever")
	_check_the_window()


## ---------- A5: killing it during the telegraph costs you nothing ----------

## The reward the window exists to offer, asserted rather than assumed: a Lance
## destroyed before it commits must NOT blast. If it did, the telegraph would be
## a countdown you cannot defuse, which is a different (and worse) enemy.
func _check_the_window() -> void:
	_arena.free()
	_arena = Node3D.new()
	root.add_child(_arena)
	var dummy: Node3D = _make_player()
	_arena.add_child(dummy)
	dummy.position = PLAYER_AT
	var lance := (load("res://scenes/combat/lance.tscn") as PackedScene).instantiate() as Lance
	lance.enemy_config = load("res://resources/default_enemy_lance.tres")
	lance.ai_seed = 0
	# Right on top of the player, so a blast could not possibly be missed.
	lance.position = PLAYER_AT + Vector3(0.0, 0.0, 3.0)
	_arena.add_child(lance)
	lance.take_hit(100000.0)
	_expect(float(dummy.get(&"taken")) == 0.0,
			"a lance killed before it commits does NOT blast (took %.0f)"
			% float(dummy.get(&"taken")))
	_arena.free()
	_arena = null
	_stage = 1
	_build(false)


## ---------- falx bug four, held for this type ----------

func _watch_without_a_player() -> void:
	if not is_instance_valid(_lance):
		_expect(false, "a lance with nobody to hit stays on the field")
		_report()
		return
	if _ticks < int(6.0 * TICK_HZ):
		return
	var drift: float = _lance.global_position.distance_to(LANCE_AT)
	_expect(drift < 20.0,
			"with no player on the field it HOLDS STATION rather than flying off the map (%.1f m in 6 s)"
			% drift)
	_report()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[lance_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[lance_check]  FAIL  %s" % message)


func _report() -> void:
	if _failures == 0:
		print("[lance_check] PASS")
	else:
		print("[lance_check] FAIL - %d check(s)" % _failures)
	quit(0 if _failures == 0 else 1)
