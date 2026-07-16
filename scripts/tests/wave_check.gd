extends SceneTree

## Headless wave-flow regression (roadmap M3): arming starts a run and
## spawns wave 1; clearing it brings a bigger wave 2 after the intermission;
## player death ends the run, despawns enemies, and reports the summary.
##
## Run: <godot> --headless -s scripts/tests/wave_check.gd --path .

const MAX_SECONDS: float = 25.0

var _main: Node3D
var _drone: FlightController
var _director: WaveDirector
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
		print("[wave_check] FAIL: timed out in phase %d (enemies %d)"
				% [_phase, _enemy_count()])
		quit(1)
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_setup()
			_phase = 1
		1:
			# Run started on arm; wave 1 should spawn base_enemies.
			if _enemy_count() == 2 and _director.wave == 1:
				print("[wave_check] wave 1 spawned (%d enemies)" % _enemy_count())
				for enemy: Node in get_nodes_in_group(&"enemies"):
					enemy.call(&"take_hit", 99999.0)
				_phase = 2
		2:
			# Intermission (shortened) then wave 2 with one more enemy.
			if _director.wave == 2 and _enemy_count() == 3:
				print("[wave_check] wave 2 spawned (%d enemies)" % _enemy_count())
				_drone.take_hit(99999.0)
				_phase = 3
		3:
			if not _director.running and _enemy_count() == 0:
				_report()


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_director = _main.get_node("WaveDirector") as WaveDirector
	var config: CombatConfig = _main.get("combat_config")
	# Deterministic test conditions on the shared config instance: fast
	# intermission, harmless enemies, turrets out of the fight. Every field
	# the assertions depend on is pinned explicitly — main auto-loads the
	# pilot's saved combat config, which can carry any difficulty tuning.
	config.wave_intermission = 0.25
	config.enemy_damage = 0.0
	config.turret_range = 0.0
	config.wave_base_enemies = 2.0
	config.wave_growth = 1.0
	config.sortie_waves = 3.0
	config.sortie_enemy_bonus = 1.0
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	_director.run_ended.connect(func(sorties: int, waves: int, kills: int) -> void:
		_run_end_report = [sorties, waves, kills])


func _report() -> void:
	var score: int = _main.get("score")
	print("[wave_check] run ended: report %s, score %d, kills %d"
			% [str(_run_end_report), score, _director.kills])
	# Died mid-wave 2 of sortie 1: no sortie cleared, one wave cleared, 2 kills.
	var ok: bool = _run_end_report.size() == 3 \
			and _run_end_report[0] == 0 \
			and _run_end_report[1] == 1 \
			and _run_end_report[2] == 2 \
			and score > 0
	print("[wave_check] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
