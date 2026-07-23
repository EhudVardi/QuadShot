class_name RaiderPack
extends Node3D

## A group of raiders measured as ONE unit (GAMEPLAY-DESIGN v1.29 → v1.33).
##
## The shipped game spawns raiders SIMULTANEOUSLY — wave_director's count
## formula scales every wave and sortie — but every `x Raider` cell in the
## matrix was 1-vs-1, so "flak really helps destroy groups of raiders" (the
## human's v1.29 feel report) had zero instrument coverage. This fixture
## mirrors gnat_swarm's external interface (destroyed / cleared /
## nearest_body / ai_seed / enemy_config) so the harness treats a raider
## group exactly like the cloud it already knows how to measure.
##
## A measurement grouping today, NOT a game entity: waves still spawn raiders
## individually. If a composer-era formation (P2.3) ever wants a pack that
## arrives as a unit, this node is ready — but nothing ships through it yet.

signal destroyed(points: float)
signal cleared

const RAIDER_SCENE: PackedScene = preload("res://scenes/combat/enemy_drone.tscn")
## Lateral spacing between bodies at spawn (m) — a loose line abreast, the
## shape a mid-wave group effectively arrives in. Part of the ruler: change it
## and measured splash/exchange numbers mean something else.
const SPACING_M: float = 8.0
## Depth stagger per body off the line's center (m), so the group is not a
## firing-squad wall and the flak bench cannot thread one lucky shell.
const STAGGER_M: float = 4.0

@export var enemy_config: EnemyConfig
## Bodies in the pack. 3 = wave 2 of sortie 1 in a shipped run
## (wave_base_enemies 2 + wave_growth 1) — the first "group" moment a player
## meets. A ruler constant, like the bench windows: stated, not tuned.
@export var pack_n: int = 3
## Per-rep determinism (P4.8): each body derives its own seed (seed*16+i), so
## rep N is the same three raiders flying the same three lives, run after run.
@export var ai_seed: int = -1

## The live bodies, for benches that must hook each one (Health.struck).
var bodies: Array[Node3D] = []

var _alive: int = 0


func _ready() -> void:
	_alive = pack_n
	for i: int in pack_n:
		var raider: Node3D = RAIDER_SCENE.instantiate() as Node3D
		if enemy_config != null:
			raider.set(&"enemy_config", enemy_config)
		if ai_seed >= 0:
			raider.set(&"ai_seed", ai_seed * 16 + i)
		# Positioned BEFORE entering the tree: a raider takes its wander home
		# from its spawn point in _ready — the same gotcha the swarm and the
		# matchup harness already document.
		var slot: float = float(i) - float(pack_n - 1) * 0.5
		raider.position = Vector3(slot * SPACING_M, 0.0, absf(slot) * STAGGER_M)
		add_child(raider)
		bodies.append(raider)
		(raider as Object).connect(&"destroyed", _on_body_destroyed)


func _on_body_destroyed(points: float) -> void:
	_alive -= 1
	destroyed.emit(points)
	if _alive <= 0:
		cleared.emit()


## The same contract as gnat_swarm's: the nearest LIVE body, or null when the
## pack is spent — what a pilot actually aims at when a group arrives.
func nearest_body(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for body: Node3D in bodies:
		if not is_instance_valid(body):
			continue
		var d: float = from.distance_squared_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best
