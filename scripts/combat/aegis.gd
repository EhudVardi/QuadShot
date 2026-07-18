class_name Aegis
extends CharacterBody3D

## Aegis — shielded bomber, the ticking bomb (GAMEPLAY-DESIGN P4.2).
##
## The one roster member that does not care about you. It flies a strike route
## toward a friendly asset at a walking pace, does not evade, does not shoot,
## and detonates on arrival. Every second it stays alive is a countdown, so it
## converts the fight from "can I kill this" into "can I kill this IN TIME" —
## a priority call rather than a duel.
##
## Its shield (health.gd) gates hull behind a per-hit threshold, so the answer
## has to arrive in big pieces: chip guns are hard-countered (P4.3 `--`),
## burst and missiles crack it (`++`). Cracking opens a timed window before
## regen closes it again, which is when the gun finally earns its keep — the
## combo, not the gun alone.

signal destroyed(points: float)
## Reached its target: the player failed the intercept. Distinct from
## destroyed, because these are opposite outcomes and the score must not
## confuse them.
signal detonated

## Encounter-design constants (not flight/input physics).
const ARRIVE_RADIUS: float = 3.0
const DEFAULT_ROUTE_LENGTH: float = 120.0

@export var enemy_config: EnemyConfig
## Dev-room affordance (per instance, off everywhere else): instead of being
## spent on arrival, the bomber restarts its run at full shield. Cracking a
## shield is a skill worth practising more than once per launch.
@export var loop_route: bool = false

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

## Where the strike route ends. Set before the node enters the tree; if it is
## left unset the bomber flies its own heading for DEFAULT_ROUTE_LENGTH, so a
## specimen dropped into a map still behaves like a bomber.
var route_end: Vector3 = Vector3.INF

@onready var _visual: Node3D = $Visual
@onready var _shield_visual: MeshInstance3D = $Visual/Shield
@onready var _health: Health = $Health

var _shield_flash: float = 0.0
var _route_start: Vector3


func _ready() -> void:
	_route_start = global_position
	if route_end == Vector3.INF:
		route_end = global_position - global_basis.z * DEFAULT_ROUTE_LENGTH
	_health.max_health = enemy_config.hull
	_health.configure_shield(enemy_config)
	_health.revive()
	_health.died.connect(_on_died)
	_health.shield_absorbed.connect(_on_shield_absorbed)
	_health.shield_broken.connect(_on_shield_broken)


func take_hit(damage: float) -> void:
	_health.take(damage)


func _physics_process(delta: float) -> void:
	var offset: Vector3 = route_end - global_position
	if offset.length() < ARRIVE_RADIUS:
		_detonate()
		return
	# No evasion, no arrival easing: it holds its route speed until it is on
	# top of the target. The telegraph is that you can see exactly where it is
	# going and exactly how long you have.
	velocity = velocity.move_toward(offset.normalized() * enemy_config.speed,
			enemy_config.accel * delta)
	move_and_slide()
	_face_route(delta)
	_update_shield_visual(delta)


func _face_route(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 1.0:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z),
				1.0 - exp(-3.0 * delta))


## The shield is the type's whole readability problem: a player whose shots do
## nothing must be able to SEE why. The bubble is visible only while the shield
## holds, and flares on every absorbed hit.
func _update_shield_visual(delta: float) -> void:
	_shield_flash = maxf(_shield_flash - delta * 3.0, 0.0)
	var up: bool = _health.shielded()
	_shield_visual.visible = up
	if up:
		var material: StandardMaterial3D = \
				_shield_visual.get_surface_override_material(0) as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 0.6 + _shield_flash * 3.0


func _on_shield_absorbed(_amount: float) -> void:
	_shield_flash = 1.0
	# Stands in as a ricochet until the bank grows a dedicated shield sound.
	SoundBank.play_at(&"shot", global_position, -14.0, 0.4)


func _on_shield_broken() -> void:
	_shield_visual.visible = false
	Effects.explosion(get_tree().root, global_position, 0.7)


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position, 2.0)
	destroyed.emit(enemy_config.points)
	queue_free()


## Route complete: the bomb lands. The bomber is spent either way, but this is
## the player losing, so it pays no points.
func _detonate() -> void:
	Effects.explosion(get_tree().root, route_end, 3.0)
	detonated.emit()
	if loop_route:
		global_position = _route_start
		velocity = Vector3.ZERO
		_health.revive()
		return
	queue_free()
