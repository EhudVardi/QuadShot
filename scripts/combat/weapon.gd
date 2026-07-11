class_name Weapon
extends Node3D

## Player blaster. Mounted under the FPV camera so it fires along the view
## axis — the screen-center reticle is always truthful, regardless of camera
## uptilt. Fires only while armed.

@export var combat_config: CombatConfig

## Test hook (scripts/tests/combat_check.gd): forces the trigger down.
var fire_override: bool = false

var _cooldown: float = 0.0
var _drone: FlightController
var _pool: ProjectilePool


func _ready() -> void:
	_drone = owner as FlightController


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _pool == null:
		_pool = get_tree().get_first_node_in_group(&"projectile_pool") as ProjectilePool
		if _pool == null:
			return
	var trigger_down: bool = fire_override or Input.is_action_pressed(&"fire")
	if trigger_down and _drone.armed and _cooldown <= 0.0:
		_fire()
		_cooldown = 1.0 / (combat_config.fire_rate * RunMods.current.fire_rate_mult)


func _fire() -> void:
	var direction: Vector3 = -global_basis.z
	var velocity: Vector3 = direction * combat_config.muzzle_speed \
			+ _drone.linear_velocity * combat_config.inherit_velocity
	# Spawn clear of the drone's own collider (also excluded by RID).
	var origin: Vector3 = global_position + direction * 0.4
	_pool.fire(origin, velocity,
			combat_config.projectile_damage * RunMods.current.damage_mult, _drone.team,
			[_drone.get_rid()], combat_config.projectile_gravity_scale,
			combat_config.projectile_lifetime)
	SoundBank.play_at(&"shot", origin, -6.0, 0.12)
