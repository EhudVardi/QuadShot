class_name CombatConfig
extends TunableConfig

## Combat/balance tunables (roadmap M1/M2), live-editable in the overlay
## exactly like FlightConfig. Shared instance: weapon, targets and main all
## export the same default_combat_config.tres.
##
## PLAYER SIDE ONLY (GAMEPLAY-DESIGN P4.8): the enemy_* and turret_* groups
## moved out to per-type EnemyConfig .tres files, so the bestiary is tuned one
## row at a time and CombatConfig means "the player's weapons and the run".
## Saved user configs carrying the old fields load fine — copy_from only reads
## properties this class still declares.

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

@export_group("Flak pod")
## The slice's third weapon (GAMEPLAY-DESIGN P3.1 / P4.10): a proximity-fused
## burst shell that detonates into a fragment cloud. Its whole reason to exist
## is the P4.3 flak column — `++` on gnats, `--` on shields — and the shape of
## that answer lives in these numbers rather than in any special-case code:
## small per-body damage (under the aegis's 40 break threshold, so it splashes
## off exactly like the chip gun) delivered to EVERY body in a radius.
@export var flak_fire_rate: float = 2.5
@export var flak_muzzle_speed: float = 70.0
## Heavier, slower shell than a bolt: more drop, which is what keeps flak a
## short-range weapon without a hard range cutoff.
@export var flak_shell_gravity_scale: float = 0.4
## Flight time before the shell airbursts on its own — the effective range.
@export var flak_shell_lifetime: float = 1.4
## Travel before the fuse arms, meters. Without it the shell would detonate on
## a hostile the muzzle is already touching.
@export var flak_arm_distance: float = 5.0
## Proximity fuse: burst when a hostile comes within this range of the shell.
## Deliberately SMALLER than the burst radius so the shell flies INTO a cloud
## before it goes off — fragments from the middle of the pack, not its face.
@export var flak_fuse_radius: float = 3.5
## Everything hostile inside this radius of the burst takes flak_damage.
@export var flak_burst_radius: float = 6.0
## Damage per body caught in the burst. Flat, not falloff — see flak_shell.gd.
@export var flak_damage: float = 10.0

@export_group("Player")
@export var player_max_health: float = 100.0
## Crash impacts below this delta-v (m/s) are free; above it they hurt.
@export var crash_damage_speed: float = 12.0
## Damage per m/s of delta-v beyond the free threshold.
@export var crash_damage_scale: float = 6.0
@export var respawn_delay: float = 2.5

@export_group("Targets")
@export var target_points: float = 100.0
@export var target_respawn_delay: float = 8.0

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
## Missile director (FCS): with missile_auto_switch on, a full lock held
## stable for this long auto-launches. The HUD winds an arc around the lock
## diamond while it counts.
@export var missile_auto_hold_s: float = 0.4

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
