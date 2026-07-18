class_name GnatSwarm
extends Node3D

## A gnat pack (GAMEPLAY-DESIGN P4.2 "Gnat — swarm drone", P4.q5 steered).
##
## THE CLOUD IS THE UNIT. This node is the combatant; the Gnat bodies under it
## are its hit points, spread across space. It runs a cheap kinematic boid
## model for the whole pack in one loop — separation, cohesion, pursuit, plus
## a wander term so the cloud boils instead of marching — and stings on
## contact. No per-body AI, no rigid bodies, no physics queries per gnat.
##
## Web role (P4.3): individual gnats are trivially dodged, so the pack punishes
## single-target answers by arithmetic — one missile per gnat is bankruptcy —
## and rewards area weapons and kiting. That row of the matrix is the reason
## this type exists, and the pack_size knob is the row's dial.

## Per body, so score and kill accounting match every other roster type.
signal destroyed(points: float)
## The pack — the actual unit — is gone. This is the "enemy defeated" event.
signal cleared

## Encounter-design constants (not flight/input physics).
const MIN_ALTITUDE: float = 2.0
const SPAWN_SPREAD: float = 4.0

@export var enemy_config: EnemyConfig
## Fixed RNG seed for the harness (P4.8 determinism): -1 randomizes.
@export var ai_seed: int = -1

const GNAT_SCENE: PackedScene = preload("res://scenes/combat/gnat.tscn")

## Bodies the player actually shot down, as opposed to ones that spent
## themselves stinging. The harness reads this to tell a real win from a pack
## that simply ran out of bodies on the player's hull.
var shot_down: int = 0

var _bodies: Array[Gnat] = []
var _player: FlightController
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if ai_seed >= 0:
		_rng.seed = ai_seed
	else:
		_rng.randomize()
	_spawn_pack()


## Nearest live body to a point — the harness's aim hook, and the shape any
## future FCS target selection would want against a distributed enemy.
func nearest_body(from: Vector3) -> Gnat:
	var best: Gnat = null
	var best_distance: float = INF
	for body: Gnat in _bodies:
		if not is_instance_valid(body):
			continue
		var distance: float = body.global_position.distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func alive_count() -> int:
	return _bodies.size()


func _spawn_pack() -> void:
	for i: int in maxi(int(enemy_config.pack_size), 1):
		var gnat: Gnat = GNAT_SCENE.instantiate() as Gnat
		add_child(gnat)
		gnat.global_position = global_position + Vector3(
				_rng.randf_range(-SPAWN_SPREAD, SPAWN_SPREAD),
				_rng.randf_range(-SPAWN_SPREAD * 0.5, SPAWN_SPREAD * 0.5),
				_rng.randf_range(-SPAWN_SPREAD, SPAWN_SPREAD))
		gnat.setup(enemy_config.hull)
		gnat.killed.connect(_on_gnat_killed)
		_bodies.append(gnat)


func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as FlightController
	if _bodies.is_empty():
		return

	# One pass to learn the pack's shape, then one pass to steer it. n is <= 12
	# by design, so the O(n^2) neighbour loop is cheaper than any structure that
	# would avoid it.
	var center: Vector3 = Vector3.ZERO
	for body: Gnat in _bodies:
		center += body.global_position
	center /= float(_bodies.size())

	var chasing: bool = _can_engage()
	for body: Gnat in _bodies:
		var steer: Vector3 = _steer_for(body, center, chasing)
		var desired: Vector3 = steer.normalized() * enemy_config.speed \
				if steer.length() > 0.001 else Vector3.ZERO
		body.velocity = body.velocity.move_toward(desired,
				enemy_config.accel * delta)
		var next: Vector3 = body.global_position + body.velocity * delta
		next.y = maxf(next.y, MIN_ALTITUDE)
		body.global_position = next

	if chasing:
		_resolve_stings()


func _steer_for(body: Gnat, center: Vector3, chasing: bool) -> Vector3:
	var position: Vector3 = body.global_position

	# Separation: push out of any neighbour inside the spacing radius, harder
	# the closer it is. Without this the pack collapses to a single point and
	# stops reading as a cloud.
	var separation: Vector3 = Vector3.ZERO
	for other: Gnat in _bodies:
		if other == body:
			continue
		var offset: Vector3 = position - other.global_position
		var distance: float = offset.length()
		if distance < enemy_config.swarm_spacing and distance > 0.001:
			separation += offset / distance \
					* (1.0 - distance / enemy_config.swarm_spacing)

	var cohesion: Vector3 = center - position
	if cohesion.length() > 0.001:
		cohesion = cohesion.normalized()

	# Wander: a per-body random walk. This is what makes the cloud boil rather
	# than fly in formation, and it is why individual gnats are dodgeable.
	var jitter := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0))

	var pursuit: Vector3 = Vector3.ZERO
	if chasing:
		pursuit = (_player.global_position - position).normalized()

	return separation * enemy_config.swarm_separation_gain \
			+ cohesion * enemy_config.swarm_cohesion_gain \
			+ pursuit * enemy_config.swarm_pursuit_gain \
			+ jitter * enemy_config.swarm_jitter


func _can_engage() -> bool:
	if _player == null:
		return false
	# visible=false is the player's death state (main.gd).
	if not _player.armed or not _player.visible:
		return false
	return global_position.distance_to(_player.global_position) \
			< enemy_config.sight_range + SPAWN_SPREAD * 4.0


## Contact detonation (P4.2 "collision sting"): a body that reaches the player
## spends itself for a bite of hull. Done as a distance test rather than
## physics contacts — twelve bodies, one loop, no collision callbacks.
func _resolve_stings() -> void:
	var sting_squared: float = enemy_config.swarm_sting_radius \
			* enemy_config.swarm_sting_radius
	for body: Gnat in _bodies.duplicate():
		if not is_instance_valid(body):
			continue
		if body.global_position.distance_squared_to(_player.global_position) \
				> sting_squared:
			continue
		# Feed the damage model's directional wound (D2) exactly as a bolt
		# does, so a sting frays the motor on the side it came from.
		_player.last_hit_direction = (body.global_position
				- _player.global_position).normalized()
		_player.take_hit(enemy_config.damage)
		SoundBank.play_at(&"explosion", body.global_position, -10.0, 0.5)
		body.die(false)


func _on_gnat_killed(gnat: Gnat, scored: bool) -> void:
	_bodies.erase(gnat)
	# Only shot-down bodies pay out. A pack that stings itself to nothing has
	# won its trade, and must never bank points for the player on the way.
	if scored:
		shot_down += 1
		destroyed.emit(enemy_config.points)
	if _bodies.is_empty():
		cleared.emit()
		queue_free()
