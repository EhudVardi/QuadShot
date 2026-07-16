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
## Fire-control assist: the blaster auto-fires when a hostile's predicted
## ballistic miss distance falls under this (meters). 0 = off (manual trigger
## only). Prototype of the FCS equipment family (GAMEPLAY-DESIGN.md, P3) —
## a dev knob today, an acquirable asset later.
@export var fire_assist_miss_m: float = 0.0
## Hostiles beyond this range are ignored by the fire assist.
@export var fire_assist_range: float = 55.0

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
@export var turret_points: float = 250.0

@export_group("Targets")
@export var target_points: float = 100.0
@export var target_respawn_delay: float = 8.0

@export_group("Enemies")
@export var enemy_health: float = 40.0
@export var enemy_points: float = 150.0
@export var enemy_speed: float = 14.0
@export var enemy_accel: float = 18.0
@export var enemy_sight_range: float = 60.0
## Enemies orbit the player at roughly this distance while attacking.
@export var enemy_preferred_range: float = 18.0
@export var enemy_fire_rate: float = 1.5
@export var enemy_muzzle_speed: float = 45.0
@export var enemy_damage: float = 8.0
## Random cone added to enemy aim — the dodgeability knob.
@export var enemy_aim_jitter_deg: float = 3.0

@export_group("Missiles")
@export var missile_lock_range: float = 60.0
## Half-angle of the lock cone around the camera axis.
@export var missile_lock_cone_deg: float = 12.0
## Seconds the target must stay in the cone to lock.
@export var missile_lock_time: float = 0.9
@export var missile_speed: float = 50.0
@export var missile_turn_rate_deg: float = 180.0
@export var missile_damage: float = 60.0
@export var missile_cooldown: float = 3.0
## Detonation distance to the locked target.
@export var missile_prox_radius: float = 2.5
@export var missile_lifetime: float = 7.0

@export_group("Waves")
@export var wave_base_enemies: float = 2.0
## Extra enemies added per wave.
@export var wave_growth: float = 1.0
@export var wave_intermission: float = 8.0
## Waves per sortie; clearing them lights the exit gate (roadmap M4).
@export var sortie_waves: float = 3.0
## Extra enemies per wave for each sortie beyond the first.
@export var sortie_enemy_bonus: float = 1.0
## Kills within this window raise the score multiplier.
@export var combo_window: float = 4.0
@export var combo_max: float = 5.0


const SAVE_PATH: String = "user://combat_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_combat_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
