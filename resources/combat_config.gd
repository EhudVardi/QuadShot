class_name CombatConfig
extends TunableConfig

## Combat/balance tunables (roadmap M1/M2), live-editable in the overlay
## exactly like FlightConfig. Shared instance: weapon, turrets, targets and
## main all export the same default_combat_config.tres.

@export_group("Weapon")
@export var fire_rate: float = 10.0
@export var muzzle_speed: float = 90.0
@export var projectile_damage: float = 25.0
@export var projectile_lifetime: float = 3.0
## Fraction of normal gravity applied to projectiles — a little drop makes
## leading targets a skill.
@export var projectile_gravity_scale: float = 0.3
## Fraction of the shooter's velocity added to the projectile.
@export var inherit_velocity: float = 1.0

@export_group("Player")
@export var player_max_health: float = 100.0
## Crash impacts below this delta-v (m/s) are free; above it they hurt.
@export var crash_damage_speed: float = 12.0
## Damage per m/s of delta-v beyond the free threshold.
@export var crash_damage_scale: float = 6.0
@export var respawn_delay: float = 2.5

@export_group("Turrets")
@export var turret_health: float = 50.0
@export var turret_range: float = 45.0
@export var turret_fire_rate: float = 2.0
@export var turret_muzzle_speed: float = 55.0
@export var turret_damage: float = 10.0
@export var turret_turn_speed_deg: float = 120.0
@export var turret_respawn_delay: float = 20.0

@export_group("Targets")
@export var target_points: float = 100.0
@export var target_respawn_delay: float = 8.0


const SAVE_PATH: String = "user://combat_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_combat_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
