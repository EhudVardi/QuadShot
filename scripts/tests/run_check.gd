extends SceneTree

## Headless run-structure regression (roadmap M4): clearing a sortie's only
## wave opens the exit gate, flying through it opens the paused upgrade
## draft, picking an option changes RunMods and launches a bigger sortie 2,
## and death records the run in the profile. The player's real profile is
## backed up and restored so test runs never pollute it.
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
var _profile_backup: Variant = null


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
		print("[run_check] FAIL: timed out in phase %d (enemies %d)"
				% [_phase, _enemy_count()])
		_finish(false)
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_setup()
			_phase = 1
		1:
			# Sortie 1 has a single (shortened) wave of base_enemies.
			if _director.sortie == 1 and _director.wave == 1 \
					and _enemy_count() == 2:
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
			# Sortie 2 wave 1: base 2 + sortie_enemy_bonus 1 = 3 hostiles.
			if _director.sortie == 2 and _enemy_count() == 3:
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


func _mods_changed() -> bool:
	var mods: RunMods = RunMods.current
	var fresh := RunMods.new()
	return mods.fire_rate_mult != fresh.fire_rate_mult \
			or mods.damage_mult != fresh.damage_mult \
			or mods.missile_cooldown_mult != fresh.missile_cooldown_mult \
			or mods.lock_time_mult != fresh.lock_time_mult \
			or mods.lock_cone_mult != fresh.lock_cone_mult \
			or mods.max_health_bonus != fresh.max_health_bonus \
			or mods.regen_rate != fresh.regen_rate \
			or mods.score_mult != fresh.score_mult


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_director = _main.get_node("WaveDirector") as WaveDirector
	_gate = _main.get_node("ExitGate") as ExitGate
	_draft = _main.get_node("DraftScreen") as DraftScreen
	if FileAccess.file_exists(PROFILE_PATH):
		_profile_backup = FileAccess.get_file_as_string(PROFILE_PATH)
	var config: CombatConfig = _main.get("combat_config")
	# One wave per sortie and a defanged opposition for determinism.
	config.sortie_waves = 1.0
	config.wave_intermission = 0.25
	config.enemy_damage = 0.0
	config.turret_range = 0.0
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	_director.run_ended.connect(func(sorties: int, waves: int, kills: int) -> void:
		_run_end_report = [sorties, waves, kills])


func _report() -> void:
	var profile_ok: bool = false
	if FileAccess.file_exists(PROFILE_PATH):
		var data: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(PROFILE_PATH))
		profile_ok = data is Dictionary and int(data.get("runs", 0)) > 0
	var score: int = _main.get("score")
	print("[run_check] run ended: report %s, score %d, profile ok %s"
			% [str(_run_end_report), score, str(profile_ok)])
	# Died in sortie 2: one sortie and one wave cleared, both kills in wave 1.
	var ok: bool = _run_end_report == [1, 1, 2] and score > 0 and profile_ok
	_finish(ok)


func _finish(ok: bool) -> void:
	# Leave the player's real profile exactly as we found it.
	if _profile_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	else:
		var file: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_profile_backup)
	print("[run_check] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
