class_name WaveDirector
extends Node

## Encounter director (roadmap M3/M4). A run is a chain of sorties: each
## sortie is a few escalating waves of enemy drones spawned in a ring around
## the arena; clearing the last wave opens the exit gate, and flying through
## it starts the next, harder sortie. Player death ends the run. Kill
## accounting flows through here so main only sees score events.

signal wave_changed(sortie: int, wave: int, remaining: int)
signal enemy_destroyed(points: float)
signal sortie_cleared(sortie: int)
signal run_ended(sorties_cleared: int, waves_cleared: int, kills: int)

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/enemy_drone.tscn")
## Spawn ring around the arena's rough center (encounter-design constants,
## not flight/input physics).
const ARENA_CENTER := Vector3(-18.0, 0.0, -15.0)
const SPAWN_RADIUS_MIN: float = 40.0
const SPAWN_RADIUS_MAX: float = 70.0
const SPAWN_HEIGHT_MIN: float = 6.0
const SPAWN_HEIGHT_MAX: float = 18.0

@export var combat_config: CombatConfig

var sortie: int = 0
## Wave number within the current sortie (resets each sortie).
var wave: int = 0
var waves_cleared: int = 0
var kills: int = 0
var running: bool = false
## True between clearing a sortie's last wave and the player taking the gate.
var awaiting_gate: bool = false

var _remaining: int = 0
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
	_next_wave()


func end_run() -> void:
	if not running:
		return
	running = false
	# Dying with the gate open still credits the sortie — its waves were won.
	var sorties_cleared: int = sortie if awaiting_gate else sortie - 1
	awaiting_gate = false
	run_ended.emit(maxi(sorties_cleared, 0), waves_cleared, kills)
	# Quiet despawn: queue_free without take_hit awards no points.
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_remaining = 0


## Called by main after the player flies the exit gate (and, once drafts
## exist, picks an upgrade).
func advance_sortie() -> void:
	if not running or not awaiting_gate:
		return
	awaiting_gate = false
	sortie += 1
	wave = 0
	_next_wave()


func _next_wave() -> void:
	if not running or awaiting_gate:
		return
	wave += 1
	var count: int = maxi(int(combat_config.wave_base_enemies
			+ combat_config.wave_growth * float(wave - 1)
			+ combat_config.sortie_enemy_bonus * float(sortie - 1)), 1)
	_remaining = count
	for i: int in count:
		_spawn_enemy()
	Blackbox.log_event(&"wave", "s%d w%d" % [sortie, wave], float(_remaining))
	wave_changed.emit(sortie, wave, _remaining)


func _spawn_enemy() -> void:
	var enemy: EnemyDrone = ENEMY_SCENE.instantiate() as EnemyDrone
	get_parent().add_child(enemy)
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = _rng.randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	enemy.global_position = ARENA_CENTER + Vector3(
			cos(angle) * radius,
			_rng.randf_range(SPAWN_HEIGHT_MIN, SPAWN_HEIGHT_MAX),
			sin(angle) * radius)
	enemy.destroyed.connect(_on_enemy_destroyed)
	Blackbox.log_event(&"spawn", "raider", 0.0, enemy.global_position)


func _on_enemy_destroyed(points: float) -> void:
	kills += 1
	_remaining -= 1
	enemy_destroyed.emit(points)
	wave_changed.emit(sortie, wave, _remaining)
	if _remaining > 0 or not running:
		return
	waves_cleared += 1
	if wave >= int(combat_config.sortie_waves):
		awaiting_gate = true
		sortie_cleared.emit(sortie)
	else:
		get_tree().create_timer(combat_config.wave_intermission).timeout.connect(_next_wave)
