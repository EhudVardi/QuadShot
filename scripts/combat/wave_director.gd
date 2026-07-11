class_name WaveDirector
extends Node

## Encounter director (roadmap M3). A run starts when the player arms,
## spawns escalating waves of enemy drones in a ring around the arena, and
## ends on player death. Kill accounting flows through here so main only
## sees score events.

signal wave_changed(wave: int, remaining: int)
signal enemy_destroyed(points: float)
signal run_ended(waves_cleared: int, kills: int)

const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/enemy_drone.tscn")
## Spawn ring around the arena's rough center (encounter-design constants,
## not flight/input physics).
const ARENA_CENTER := Vector3(-18.0, 0.0, -15.0)
const SPAWN_RADIUS_MIN: float = 40.0
const SPAWN_RADIUS_MAX: float = 70.0
const SPAWN_HEIGHT_MIN: float = 6.0
const SPAWN_HEIGHT_MAX: float = 18.0

@export var combat_config: CombatConfig

var wave: int = 0
var kills: int = 0
var running: bool = false

var _remaining: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func start_run() -> void:
	if running:
		return
	running = true
	wave = 0
	kills = 0
	_next_wave()


func end_run() -> void:
	if not running:
		return
	running = false
	var cleared: int = wave - 1 if _remaining > 0 else wave
	run_ended.emit(maxi(cleared, 0), kills)
	# Quiet despawn: queue_free without take_hit awards no points.
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	_remaining = 0


func _next_wave() -> void:
	if not running:
		return
	wave += 1
	var count: int = maxi(int(combat_config.wave_base_enemies
			+ combat_config.wave_growth * float(wave - 1)), 1)
	_remaining = count
	for i: int in count:
		_spawn_enemy()
	wave_changed.emit(wave, _remaining)


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


func _on_enemy_destroyed(points: float) -> void:
	kills += 1
	_remaining -= 1
	enemy_destroyed.emit(points)
	wave_changed.emit(wave, _remaining)
	if _remaining <= 0 and running:
		get_tree().create_timer(combat_config.wave_intermission).timeout.connect(_next_wave)
