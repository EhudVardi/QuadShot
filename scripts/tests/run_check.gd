extends SceneTree

## Headless run-structure regression (roadmap M4): clearing a sortie's only
## wave opens the exit gate, flying through it opens the paused upgrade
## draft, picking an option changes RunMods and launches a bigger sortie 2,
## and death records the run in the profile.
##
## Nothing here touches the player's real `user://profile.json` any more.
## `PlayerProfile.save()` refuses to write under the headless driver, so the
## borrow-and-restore this check used to carry is gone, and `_report` asserts
## the refusal instead — see the notes on both functions.
##
## Run: <godot> --headless -s scripts/tests/run_check.gd --path .

const MAX_SECONDS: float = 30.0
const PROFILE_PATH: String = "user://profile.json"

var _main: Node3D
var _drone: FlightController
var _director: WaveDirector
var _gate: ExitGate
var _draft: DraftScreen
var _phase: int = 0
var _ticks: int = 0
var _ticks_max: int
var _run_end_report: Array = []


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate() as Node3D
	root.add_child(_main)
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_physics_frame)


func _enemy_count() -> int:
	var count: int = 0
	for enemy: Node in get_nodes_in_group(&"enemies"):
		if not enemy.is_queued_for_deletion():
			count += 1
	return count


func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks >= _ticks_max:
		var where: String = "no director yet" if _director == null \
				else "s%d w%d, %d units" % [_director.sortie, _director.wave,
				_director.remaining]
		print("[run_check] FAIL: timed out in phase %d (%s, %d bodies)"
				% [_phase, where, _enemy_count()])
		_finish(false)
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_setup()
			_phase = 1
		1:
			# Sortie 1 has a single (shortened) wave of base_enemies. Counted
			# in UNITS: a wave's composition can include an emplacement (group
			# `turrets`) or a cloud (nine bodies, one unit), so a raw body
			# count is no longer the wave's clock — director.remaining is.
			if _director.sortie == 1 and _director.wave == 1 \
					and _director.remaining == 2:
				print("[run_check] sortie 1 wave 1 spawned")
				for enemy: Node in get_nodes_in_group(&"enemies"):
					enemy.call(&"take_hit", 99999.0)
				_phase = 2
		2:
			if _director.awaiting_gate and _gate.active:
				print("[run_check] exit gate open")
				_phase = 3
		3:
			# Hold the drone in the gate opening until the Area sees it.
			_drone.global_position = _gate.global_position
			if _draft.visible:
				print("[run_check] draft open (paused %s)" % str(paused))
				_draft.pick(0)
				_phase = 4
		4:
			# Sortie 2 wave 1: base 2 + sortie_enemy_bonus 1 = 3 units, which
			# the plan spends on an emplacement plus two raiders.
			if _director.sortie == 2 and _director.remaining == 3:
				if not _mods_changed():
					print("[run_check] FAIL: draft pick left RunMods at defaults")
					_finish(false)
					return
				print("[run_check] sortie 2 spawned, RunMods changed")
				_drone.take_hit(99999.0)
				_phase = 5
		5:
			if not _director.running and _enemy_count() == 0:
				_report()


## Did the draft pick change ANY run modifier?
##
## Compares every script property instead of a hand-listed set, and the reason
## is a real intermittent failure: the upgrade pool grew Heat Sinks and Vent
## Ports, the hand-written list did not, and the check then passed or failed
## purely on whether `draft()`'s shuffle happened to offer one of them at index
## 0. It passed alone and failed in a batch, which is the worst way for a
## regression check to behave. A generic comparison cannot drift out of date.
func _mods_changed() -> bool:
	var mods: RunMods = RunMods.current
	var fresh := RunMods.new()
	for property: Dictionary in fresh.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: StringName = property["name"]
		if mods.get(name) != fresh.get(name):
			return true
	return false


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_director = _main.get_node("WaveDirector") as WaveDirector
	_gate = _main.get_node("ExitGate") as ExitGate
	_draft = _main.get_node("DraftScreen") as DraftScreen
	var config: CombatConfig = _main.get("combat_config")
	# One wave per sortie and a defanged opposition for determinism. Every
	# field the assertions depend on is pinned explicitly — main auto-loads
	# the pilot's saved combat config, which can carry any difficulty tuning.
	config.sortie_waves = 1.0
	config.wave_intermission = 0.25
	(load("res://resources/default_enemy_raider.tres") as EnemyConfig).damage = 0.0
	(load("res://resources/default_enemy_turret.tres") as EnemyConfig).sight_range = 0.0
	config.wave_base_enemies = 2.0
	config.wave_growth = 1.0
	config.sortie_enemy_bonus = 1.0
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	_director.run_ended.connect(func(sorties: int, waves: int, kills: int) -> void:
		_run_end_report = [sorties, waves, kills])


## THE PROFILE ASSERTION HAD TO CHANGE WHEN THE PROFILE STOPPED BEING WRITTEN.
##
## This used to read `user://profile.json` back and assert `runs > 0`. That was
## a real assertion while a headless run still wrote the file — and it became a
## check that CANNOT FAIL the moment `PlayerProfile.save()` started refusing to
## write headless (2026-08-04), because the file it reads is the human's real
## career and their `runs` is 158 whatever this check does.
##
## So it asserts the two halves that still exist, and each is falsifiable:
## the recording arithmetic, and the suppression itself. The second one is what
## keeps the guard from being quietly deleted again.
func _report() -> void:
	var probe := PlayerProfile.new()
	probe.record_run(2, 7, 900)
	var recorded_ok: bool = probe.runs == 1 and probe.kills_total == 7 \
			and probe.best_score == 900 and probe.best_sorties == 2

	var before: String = FileAccess.get_file_as_string(PROFILE_PATH) \
			if FileAccess.file_exists(PROFILE_PATH) else ""
	probe.save()
	var after: String = FileAccess.get_file_as_string(PROFILE_PATH) \
			if FileAccess.file_exists(PROFILE_PATH) else ""
	var suppressed: bool = before == after

	var score: int = _main.get("score")
	print("[run_check] run ended: report %s, score %d, recording ok %s, headless save suppressed %s"
			% [str(_run_end_report), score, str(recorded_ok), str(suppressed)])
	if not recorded_ok:
		print("[run_check] FAIL: record_run did not tally the run it was given")
	if not suppressed:
		print("[run_check] FAIL: a headless save wrote the player's real profile.json")
	# Died in sortie 2: one sortie and one wave cleared, both kills in wave 1.
	var ok: bool = _run_end_report == [1, 1, 2] and score > 0 \
			and recorded_ok and suppressed
	_finish(ok)


## THE BORROW-AND-RESTORE IS GONE, and its absence is the point.
##
## This check used to copy `user://profile.json` aside and write it back here.
## That was correct and it was never the leak — `wave_check` was, and it had no
## such machinery, which is the recurring lesson: a rule kept in the CALLERS is
## a rule most callers will not keep. `PlayerProfile.save()` now refuses to
## write headless, so there is nothing to undo, and restoring by hand would mean
## this check still writes the human's real file for no reason.
##
## `_report` asserts the suppression directly, so deleting the guard fails here
## rather than silently re-arming the leak.
func _finish(ok: bool) -> void:
	print("[run_check] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
